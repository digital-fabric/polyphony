---
layout: page
title: How Fibers are Scheduled
nav_order: 3
parent: Technical Overview
permalink: /technical-overview/fiber-scheduling/
prev_title: Concurrency the Easy Way
next_title: Exception Handling
---

# How Fibers are Scheduled

Before we discuss how fibers are scheduled in Polyphony, let's examine how
switching between fibers works in Ruby.

Ruby provides two mechanisms for transferring control between fibers:
`Fiber#resume` /`Fiber.yield` and `Fiber#transfer`. The first is inherently
asymmetric and is famously used for implementing generators and [resumable
enumerators](https://blog.appsignal.com/2018/11/27/ruby-magic-fibers-and-enumerators-in-ruby.html).
Here's a small example:

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

Another implication of using resume / yield is that the main fiber can't yield
away, meaning we cannot pause the main fiber using `Fiber.yield`.

The other fiber control mechanism, using `Fiber#transfer`, is fully symmetric:

```ruby
require 'fiber'

ping = Fiber.new { loop { puts "ping"; pong.transfer } }
pong = Fiber.new { loop { puts "pong"; ping.transfer } }
ping.transfer
```

`Fiber#transform` also allows using the main fiber as a general purpose
resumable execution context. Polyphony uses `Fiber#transfer` exclusively for
scheduling fibers.

## The Different Fiber states

In Polyphony, each fiber has one four possible states:

A new fiber will start in a `:waiting` state. The `#spin` global method will
create the fiber and schedule it for execution, marking it as `:runnable`. When
the fiber is run, it is in a `:running` state. Finally, when the fiber has
terminated, it transitions to the `:dead` state.

Whenever a fiber performs a blocking operation - such as waiting for a timer to
elapse, or for a socket to become readable, or for a child process to terminate -
it transitions to a `:waiting` state. Once the timer has elapsed, the socket
has become readable, or the child process has terminated, the fiber is marked as
`:runnable`. It then waits its turn to run.

## Switchpoints

A switchpoint is any point in time at which control might switch from the
currently running fiber to another fiber that is `:runnable`. This usually
occurs when the currently running fiber starts a blocking operation. It also
occurs when the running fiber has yielded control using `#snooze` or `#suspend`.
A Switchpoint will also occur when the currently running fiber has terminated.

## Scheduler-less scheduling

Polyphony relies on [libev](http://software.schmorp.de/pkg/libev.html) for
handling events such as I/O readiness, timers and signals. In most event
reactor-based libraries and frameworks, such as `nio4r`, `EventMachine` or
`node.js`, the reactor loop is run, and event callbacks are used to schedule
user-supplied code *from inside the loop*. In Polyphony, however, we have chosen
a programming model that does not use a loop to schedule fibers. In fact, in
Polyphony there's no such thing as a reactor loop, and there's no *scheduler*
per se running on a separate execution context.

Instead, Polyphony maintains for each thread a run queue, a list of `:runnable`
fibers. If no fiber is `:runnable`, the libev event reactor will be ran until
one or more events have occurred. Events are handled by adding the corresponding
fibers onto the run queue. Finally, control is transferred to the first fiber on
the run queue, which will run until it blocks or terminates, at which point
control is transferred to the next runnable fiber.

This approach has numerous benefits:

- No separate reactor fiber that needs to be resumed on each blocking operation,
  leading to less context switches, and less bookkeeping.
- Clear separation between the reactor code (the `libev` code) and the fiber
  scheduling code.
- Much less time is spent in reactor loop callbacks, letting the reactor loop
  run more efficiently.
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
waiting for a socket to be readable, or sleeping for an extended period of time.
This is especially useful when higher-level constructs are needed for
controlling multiple concurrent operations.

Polyphony provides the ability to interrupt a blocking operation by harnessing
the ability to transfer values back and forth between fibers using
`Fiber#transfer`. Whenever a waiting fiber yields control to the next scheduled
fiber, the value received upon being resumed is checked. If the value is an
exception, it will be raised in the context of the waiting fiber, effectively
signalling that the blocking operation has been unsuccessful and allowing
exception handling using the builtin mechanisms offered by Ruby, namely `rescue`
and `ensure` (see also [exception handling](exception-handling.md)).

Here's a naive implementation of a yielding I/O read operation in Polyphony (the
actual code for I/O reading in Polyphony is written in C and is a bit more
involved):

```ruby
def read_from(io)
  loop do
    result = IO.readnonblock(8192, exception: false)
    if result == :wait_readable
      wait_readable(io)
    else
      return result
    end
  end
end

def wait_readable(io)
  fiber = Fiber.current
  watcher = Gyro::IO.new(io, :read) { fiber.transfer }

  # run any scheduled fibers or run libev reactor waiting for events 
  result = GV.run

  # waiting fiber is resumed - check transferred value
  raise result if result.is_a?(Exception)
  result
ensure
  # ensure the I/O watcher is deactivated, even if exception is raised
  watcher.active = false
end
```

In the above example, the `wait_readable` method will normally wait indefinitely
until the IO object has become readable. But we could interrupt it at any time
by scheduling the corresponding fiber with an exception:

```ruby
def timeout(duration)
  fiber = Fiber.current
  interrupter = spin do
    Gyro::Timer.new(duration, 0).await
    fiber.transfer(TimerException.new)
  end
  yield
ensure
  interrupter.stop
end
```

## Fiber Scheduling in a Multithreaded Program

Polyphony performs fiber scheduling separately for each thread. Each thread,
therefore, will be able to run multiple fibers independently from other threads.

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
