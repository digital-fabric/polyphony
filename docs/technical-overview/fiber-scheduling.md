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

Ruby provides two mechanisms for transferring control between fibers:
`Fiber#resume` /`Fiber.yield` and `Fiber#transfer`. The first is inherently
asymmetric and is famously used for implementing generators and [resumable
enumerators](https://blog.appsignal.com/2018/11/27/ruby-magic-fibers-and-enumerators-in-ruby.html).
Another limiting factor of using resume / yield is that the main fiber can't
yield away, limiting its usability as a resumable fiber.

The second mechanism, using `Fiber#transfer`, is completely symmetric and allows
use of the main fiber as a general purpose resumable execution context.
Polyphony uses `Fiber#transfer` exclusively for scheduling fibers.

## Scheduler-less scheduling

Polyphony relies on [libev](http://software.schmorp.de/pkg/libev.html) for
handling events such as I/O readiness, timers and signals. In most event
reactor-based libraries and frameworks, such as `nio4r`, `EventMachine` or
`node.js`, the reactor loop is run, and event callbacks are used to schedule
user-supplied code *from inside the loop*. In Polyphony, however, we have chosen
a programming model that does not use a loop to schedule fibers. In fact, in
Polyphony there's no such thing as a reactor loop, and there's no *scheduler*
running on a separate execution context.

Instead, Polyphony maintains for each thread a list of scheduled fibers, fibers
that will be resumed once the current fiber yields control, which will occur on
every blocking operation. If no fibers are scheduled, the libev event reactor
will be ran until one or more events have occurred. Events are handled by adding
the corresponding fibers onto the *scheduled fibers* list. Finally, control is
transferred to the first scheduled fiber, which will run until it blocks or
terminates, at which point control is transferred to the next scheduled fiber.

This approach has numerous benefits:

- No separate reactor fiber that needs to be resumed on each blocking operation,
  leading to less context switches, and less bookkeeping.
- Clear separation between the reactor code (the `libev` code) and the fiber
  scheduling code.
- Much less time is spent in reactor loop callbacks, letting the reactor loop
  run more efficiently.
- Fibers are resumed outside of the event reactor code, making it easier to
  avoid race conditions and unexpected behaviours.

## A concrete example - fiber scheduling in an echo server

Here's a barebones echo server written in Polyphony:

```ruby
require 'polyphony'

server = TCPServer.open('127.0.0.1', 8081)
while (client = server.accept)
  spin do
    while (data = client.gets)
      client << ">>>you sent: #{data}"
      break if data =~ /quit/i
    end
  end
end
```

Let's examine the the flow of control in our echo server program:

<p class="img-figure"><img src="../../assets/img/echo-fibers.svg"></p>

> In the above figure, the fat blue dots represents moments at which fibers can
> be switched. The light blue horizontal arrows represent switching from one
> fiber to another. The blue vertical lines represent a train of execution on a
> single fiber.

- The main fiber (fiber 1) runs a loop waiting for incoming connections.
- The call to `server.accept` blocks, and an I/O event watcher is set up. The
  main fiber is suspended.
- Since there's no other runnable fiber, the associated event loop is run.
- An event is generated for the server's socket, and fiber 1 is added to the run
  queue.
- Fiber 1 is pulled from the run queue and resumed. The `server.accept` call
  returns a new client socket (an instance of `TCPSocket`).
- Fiber 1 continues by `spin`ning up a new fiber for handling the client. The
  new fiber (fiber 2) is added to the run queue.
- Fiber 1 goes back to waiting for an incoming connection by calling
  `server.accept` again. The call blocks, the main fiber suspends, and switches
  to the next fiber in the run queue, fiber 2.
- Fiber 2 starts a loop and calls `client.gets`. The call blocks, an I/O event
  watcher is set up, and the fiber suspends.
- Since no other fiber is runnable, the event loop is run, waiting for at least
  one event to fire.
- An event fires for the acceptor socket, and fiber 1 is put on the run queue.
- An event fires for the client socket, and fiber 2 is put on the run queue.
- Fiber 1 is resumed and spins up a new client handling fiber (fiber 3), which
  is put on the run queue.
- Fiber 1 calls `server.accept` again, and suspends, switching to the next
  runnable fiber, fiber 2.
- Fiber 2 resumes and completes reading a line from the socket.
- Fiber 2 calls `client.<<`, blocks, sets up an I/O watcher, and suspends,
  switching to the next runnable fiber, fiber 3.
- Fiber 3 resumes and calls `client.gets`. The call blocks, an I/O event watcher
  is set up, and the fiber suspends.

## Fiber states

In Polyphony, each fiber has one of the following states at any given moment:

- `:running`: this is the state of the currently running fiber.
- `:dead`: the fiber has terminated.
- `:waiting`: the fiber is suspended, waiting for something to wake it up.
- `:runnable`: the fiber is on the run queue and will be run shortly.

## Fiber scheduling and fiber switching

The Polyphony scheduling model makes a clear separation between the scheduling
of fibers and the switching of fibers. The scheduling of fibers is the act of
marking the fiber to be run at the earliest opportunity, but not immediately.
The switching of fibers is the act of transferring control to another fiber, in
this case the first fiber in the list of *currently* scheduled fibers.

The scheduling of fibers can occur at any time, either as a result of an event
occuring, an exception being raised, or using `Fiber#schedule`. The switching of
fibers will occur only when a blocking operation is started, or upon calling
`Fiber#suspend` or `Fiber#snooze`. In order to switch to a scheduled fiber,
Polyphony uses `Fiber#transfer`.

When a fiber terminates, any other scheduled fibers will be run. If no fibers
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
  watcher = Gyro::Timer.new(duration) { fiber.transfer(TimerException.new) }
  yield
ensure
  watcher.active = false
end
```
