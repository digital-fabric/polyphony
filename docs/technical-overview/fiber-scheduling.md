# How Fibers are Scheduled

Ruby provides two mechanisms for transferring control between fibers: `Fiber#resume` / `Fiber.yield` and `Fiber#transfer`. The first is inherently asymmetric and is famously used for implementing generators and [resumable enumerators](https://blog.appsignal.com/2018/11/27/ruby-magic-fibers-and-enumerators-in-ruby.html). Another limiting factor of using resume / yield is that the root fiber can't yield away, limiting its usability as a resumable fiber.

The second mechanism, using `Fiber#transfer`, is completely symmetric and allows use of the root fiber as a general purpose resumable execution context. Polyphony uses `Fiber#transfer` exclusively for scheduling fibers.

## Scheduler-less scheduling

Polyphony relies on [libev](http://software.schmorp.de/pkg/libev.html) for handling events such as I/O readiness, timers and signals. In most event reactor-based libraries and frameworks, such as `nio4r`, `EventMachine` or `node.js`, the reactor loop is run, and event callbacks are used to schedule user-supplied code *from inside the loop*. In Polyphony, however, we have chosen a programming model that does not use a loop to schedule fibers. In fact, in Polyphony there's no such thing as a reactor loop, and there's no *scheduler* running on a separate execution context.

Instead, Polyphony maintains a list of scheduled fibers, fibers that will be resumed once the current fiber yields control, which will occur on every blocking operation. If no fibers are scheduled, the libev event reactor will be ran until one or more events have occurred. Events are handled by adding the corresponding fibers onto the *scheduled fibers* list. Finally, control is transferred to the first scheduled fiber, which will run until it blocks or terminates, at which point control is transferred to the next scheduled fiber.

This approach has numerous benefits:

- No separate reactor fiber that needs to be resumed on each blocking operation, leading to less context switches, and less bookkeeping.
- Clear separation between the reactor code (the `libev` code) and the fiber scheduling code.
- Much less time is spent in reactor loop callbacks, letting the reactor loop run more efficiently.
- Fibers are resumed outside of the event reactor code, making it easier to avoid race conditions and unexpected behaviours.

## Fiber states

In Polyphony, each fiber has one of the following states at any given moment:

- `:running`: this is the state of the currently running fiber.
- `:dead`: the fiber has terminated.
- `:paused`: the fiber is paused;
- `:scheduled`: the fiber is scheduled to run soon.

## Fiber scheduling and fiber switching

The Polyphony scheduling model makes a clear separation between the scheduling of fibers and the switching of fibers. The scheduling of fibers is the act of marking the fiber to be run at the earliest opportunity, but not immediately. The switching of fibers is the act of transferring control to another fiber, in this case the first fiber in the list of *currently* scheduled fibers.

The scheduling of fibers can occur at any time, either as a result of an event occuring, an exception being raised, or using `Fiber#schedule`. The switching of fibers will occur only when a blocking operation is started, or upon calling `Fiber#suspend` or `Fiber#snooze`. In order to switch to a scheduled fiber, Polyphony uses `Fiber#transfer`.

When a fiber terminates, any other scheduled fibers will be run. If no fibers are waiting and the main fiber is done running, the Ruby process will terminate.

## Interrupting blocking operations

Sometimes it is desirable to be able to interrupt a blocking operation, such as waiting for a socket to be readable, or sleeping for an extended period of time. This is especially useful when higher-level constructs are needed for controlling multiple concurrent operations.

Polyphony provides the ability to interrupt a blocking operation by harnessing the ability to transfer values back and forth between fibers using `Fiber#transfer`. Whenever a waiting fiber yields control to the next scheduled fiber, the value received upon being resumed is checked. If the value is an exception, it will be raised in the context of the waiting fiber, effectively signalling that the blocking operation has been unsuccessful and allowing exception handling using the builtin mechanisms offered by Ruby, namely `rescue` and `ensure` (see also [exception handling](exception-handling.md)).

Here's a naive implementation of a yielding I/O read operation in Polyphony (the actual code for I/O reading in Polyphony is written in C and is a bit more involved):

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

In the above example, the `wait_readable` method will normally wait indefinitely until the IO object has become readable. But we could interrupt it at any time by scheduling the corresponding fiber with an exception:

```ruby
def timeout(duration)
  fiber = Fiber.current
  watcher = Gyro::Timer.new(duration) { fiber.transfer(TimerException.new) }
  yield
ensure
  watcher.active = false
end
```
