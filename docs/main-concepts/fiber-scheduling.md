---
layout: page
title: How Fibers are Scheduled
nav_order: 2
parent: Main Concepts
permalink: /main-concepts/fiber-scheduling/
prev_title: Concurrency the Easy Way
next_title: Exception Handling
---

# How Fibers are Scheduled

Before we discuss how fibers are scheduled in Polyphony, let's examine how
switching between fibers works in Ruby.

Ruby provides two mechanisms for transferring control between fibers:
`Fiber#resume` /`Fiber.yield` and `Fiber#transfer`. The first is inherently
asymmetric and is mostly used for implementing generators and [resumable
enumerators](https://blog.appsignal.com/2018/11/27/ruby-magic-fibers-and-enumerators-in-ruby.html).
Here's an example:

```ruby
fib = Fiber.new do
  x, y = 0, 1
  loop do
    Fiber.yield y
    x, y = y, x + y
  end
end

10.times { puts fib.resume }
```

An implication of using resume / yield is that the main fiber can't yield
away, meaning we cannot pause the main fiber using `Fiber.yield`.

The other fiber control mechanism, using `Fiber#transfer`, is fully symmetric:

```ruby
require 'fiber'

ping = Fiber.new { loop { puts "ping"; pong.transfer } }
pong = Fiber.new { loop { puts "pong"; ping.transfer } }
ping.transfer
```

`Fiber#transfer` also allows using the main fiber as a general purpose
resumable execution context. For that reason, Polyphony uses `Fiber#transfer`
exclusively for scheduling fibers. Normally, however, applications based on
Polyphony will not use this API directly.

## The Different Fiber states

In Polyphony, each fiber has one of four possible states:

- `:runnable` - a new fiber will start in the runnable state. This means it is
  placed on the thread's run queue and is now waiting its turn to be resumed.
- `:running` - once the fiber is resumed, it transitions to the running state.
  `Fiber.current.state` always returns `:running`.
- `:wait` - whenever the fiber performs a blocking operation—such as waiting for
  a timer to elapse, or for a socket to become readable—the fiber transitions to
  a waiting state. When the corresponding event occurs the fiber will transition
  to a `:runnable` state, and will be eventually resumed (`:running`).
- `:dead` - once the fiber has terminated, it transitions to the dead state.

## Switchpoints

A switchpoint is any point in time at which control *might* switch from the
currently running fiber to another fiber that is `:runnable`. This usually
occurs when the currently running fiber starts a blocking operation, such as
reading from a socket or waiting for a timer. It also occurs when the running
fiber has explicitly yielded control using `#snooze` or `#suspend`. A
Switchpoint will also occur when the currently running fiber has terminated.

## Scheduler-less scheduling

Polyphony relies on [libev](http://software.schmorp.de/pkg/libev.html) for
handling events such as I/O readiness, timers and signals. In most event
reactor-based libraries and frameworks, such as `nio4r`, `EventMachine` or
`node.js`, the entire application is run inside of a reactor loop, and event
callbacks are used to schedule user-supplied code *from inside the loop*.

In Polyphony, however, we have chosen a concurrency model that does not use a
loop to schedule fibers. In fact, in Polyphony there's no outer reactor loop,
and there's no *scheduler* per se running on a separate execution context.

Instead, Polyphony maintains for each thread a run queue, a list of `:runnable`
fibers. If no fiber is `:runnable`, Polyphony will run the libev event loop until
at least one event has occurred. Events are handled by adding the corresponding
fibers onto the run queue. Finally, control is transferred to the first fiber on
the run queue, which will run until it blocks or terminates, at which point
control is transferred to the next runnable fiber.

This approach has numerous benefits:

- No separate reactor fiber that needs to be resumed on each blocking operation,
  leading to less context switches, and less bookkeeping.
- Clear separation between the reactor code (the `libev` code) and the fiber
  scheduling code.
- Much less time is spent in event loop callbacks, letting the event loop run
  more efficiently.
- Fibers are switched outside of the event reactor code, making it easier to
  avoid race conditions and unexpected behaviours.

## Fiber scheduling and fiber switching

The Polyphony scheduling model makes a clear separation between the scheduling
of fibers and the switching of fibers. The scheduling of fibers is the act of
marking the fiber as `:runnable`, to be run at the earliest opportunity, but not
immediately. The switching of fibers is the act of actually transferring control
to another fiber, namely the first fiber in the run queue.

The scheduling of fibers can occur at any time, either as a result of an event
occuring, an exception being raised, or using `Fiber#schedule`. The switching of
fibers will occur only when the currently running fiber has reached a
switchpoint, e.g. when a blocking operation is started, or upon calling
`Fiber#suspend` or `Fiber#snooze`. As mentioned earlier, in order to switch to a
scheduled fiber, Polyphony uses `Fiber#transfer`.

When a fiber terminates, any other runnable fibers will be run. If no fibers
are waiting and the main fiber is done running, the Ruby process will terminate.

## Interrupting blocking operations

Sometimes it is desirable to be able to interrupt a blocking operation, such as
waiting for a socket to be readable, or sleeping. This is especially useful when
higher-level constructs are needed for controlling multiple concurrent
operations.

Polyphony provides the ability to interrupt a blocking operation by harnessing
the ability to transfer values back and forth between fibers using
`Fiber#transfer`. Whenever a waiting fiber yields control to the next scheduled
fiber, the value received upon being resumed is checked. If the value is an
exception, it will be raised in the context of the waiting fiber, effectively
signalling that the blocking operation has been unsuccessful and allowing
exception handling using the builtin mechanisms offered by Ruby, namely `rescue`
and `ensure` (see also [exception handling](exception-handling.md)).

This mode of operation makes implementing timeouts almost trivial:

```ruby
def with_timeout(duration)
  interruptible_fiber = Fiber.current
  timeout_fiber = spin do
    sleep duration
    interruptible_fiber.raise 'timeout'
  end
  
  # do work
  yield
ensure
  timeout_fiber.terminate
end

with_timeout(10) do
  HTTParty.get 'https://acme.com/'
end
```

## Fiber Scheduling in a Multithreaded Program

Polyphony performs fiber scheduling separately for each thread. Each thread,
therefore, will be able to run multiple fibers independently from other threads.
Multithreading in Ruby has limited benefit, due to the global virtual lock that
prevents true parallelism. But offloading work to a separate thread might be
eneficial when a Polyphonic app needs to use APIs that are not fiber-aware, such
as blocking database calls (SQLite in particular), or system calls that might
block for an extended duration.

For this, you can either spawn a new thread, or use the provided
`Polyphony::ThreadPool` class that allows you to offload work to a pool of
threads.

## The fiber scheduling algorithm in full

Here is the summary of the Polyphony scheduling algorithm:

- loop
  - pull first runnable fiber from run queue
  - if runnable fiber is not nil
    -  if the ref count greater than 0
      - increment the run_no_wait counter
      - if the run_no_wait counter is greater than 10 and greater than the run
        queue length
        - reset the run_no_wait counter
        - run the event loop once without waiting for events (using
          `EVRUN_NOWAIT`)
    - break out of the loop
  - if the ref count is 0
    - break out of the loop
  - run the event loop until one or more events are generated (using
    `EVRUN_ONCE`)
- if next runnable fiber is nil
  - return
- get scheduled resume value for next runnable fiber
- mark the next runnable fiber as not runnable
- switch to the next runnable fiber using `Fiber#transfer`
