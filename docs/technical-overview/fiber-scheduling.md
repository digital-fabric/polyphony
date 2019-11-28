# How Fibers Are Scheduled

Ruby provides two mechanisms for transferring control between fibers:
`Fiber#resume` / `Fiber.yield` and `Fiber#transfer`. The first is inherently asymmetric and is famously used
for implementing generators and [resumable enumerators](https://blog.appsignal.com/2018/11/27/ruby-magic-fibers-and-enumerators-in-ruby.html).
Another limiting factor of using resume / yield is that the root fiber can't
yield away, limiting its usability as a resumable fiber.

The second mechanism, using `Fiber#transfer`, is completely symmetric and allows
use of the root fiber as a general purpose resumable execution context.
Polyphony uses `Fiber#transfer` exclusively for scheduling fibers.

## The Reactor Fiber

Polyphony relies on [libev](http://software.schmorp.de/pkg/libev.html) for
handling events such as I/O readiness, timers and signals. The libev event loop
runs in a separate fiber (called the reactor fiber) and handles each event by 
resuming the appropriate fiber using `Fiber#transfer`. The event loop will 
continue running and scheduling fibers as long as there's active event watchers.
When all event watchers have been deactivated, the event loop terminates and
control is  transferred to the root fiber, which will either terminate the
program, or go on with other work, and possibly another run of the event loop.

## Fiber scheduling

When a new fiber is created, it is in a suspended state. To start it, it needs
to be resumed using `Fiber#transfer`. Upon performing a blocking operation, such
as `sleep` or `gets`, an event watcher will be created, and control will be
transferred to the reactor fiber, which will resume running the event loop. A
fiber waiting for an event will be resumed using `Fiber#transfer` once the event
has been received, and will continue execution until encountering another
blocking operation, at which point it will again create an event watcher and
transfer control back to the reactor fiber.

## Interrupting blocking operations

Sometimes it is desirable to be able to interrupt a blocking operation, such as
waiting for a socket to be readable, or sleeping for an extended period of time.
This is especially useful when higher-level constructs are needed for
controlling multiple concurrent operations.

Polyphony provides the ability to interrupt a blocking operation by harnessing
the ability to transfer values back and forth when using `Fiber#transfer`.
Whenever a waiting fiber transfers control to the reactor fiber, the value 
received upon being resumed is checked. If the value is an exception, it will
be raised in the context of the waiting fiber, effectively signalling that the
blocking operation has been unsuccessful and allowing exception handling using
the usual mechanisms offered by Ruby, namely `rescue` and `ensure` (see also
[exception handling](./exception-handling.md)).

Here's an siplified example of how this mechanism works when reading from an I/O
object (the actual code for I/O reading in Polyphony is written in C and a bit
more involved):

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
  watcher = Gyro::IO.new(io, :read)
  # transfer control to event loop
  result = $__reactor_fiber__.transfer
  # got control back, check if result is an exception
  raise result if result.is_a?(Exception)
  result
ensure
  watcher.active = false
end
```

In the above example, the `wait_readable` method will normally wait indefinitely
until the IO object has become readable. But we could interrupt it at any time
by scheduling the corresponding fiber with an exception.

## Deferred Operations

In addition to waiting for blocking operations, Polyphony provides numerous APIs 
for suspending and scheduling fibers:

- `Fiber#safe_transfer(value = nil)` - transfers control to another fiber with
  exception handling.
- `Fiber#schedule(value = nil)` - schedules a fiber to be resumed once the
  event loop becomes idle.
- `Kernel#snooze` - transfers control to the reactor fiber while scheduling the
  current fiber to be resumed immediately once the event loop is idle.
- `Kernel#suspend` - suspends the current fiber indefinitely by transferring
  control to the reactor fiber.

In addition, a lower level API allows running arbitrary code in the context of
the reactor loop using `Kernel#defer`. Using this API will run the given block
the next time the event loop is idle.
