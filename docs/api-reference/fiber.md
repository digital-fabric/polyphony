---
layout: page
title: ::Fiber
parent: API Reference
permalink: /api-reference/fiber/
# prev_title: Tutorial
# next_title: How Fibers are Scheduled
---
# ::Fiber

[Ruby core Fiber documentation](https://ruby-doc.org/core-2.7.0/Fiber.html)

Polyphony enhances the core `Fiber` class with APIs for scheduling, exception
handling, message passing, and more. Normally, fibers should be created using
`Object#spin` or `Fiber#spin`, but some fibers might be created implicitly when
using lazy enumerators or third party gems. For fibers created implicitly,
Polyphony provides `Fiber#setup_raw`, which enables scheduling and message
passing for such fibers.

While most work on fibers since their introduction into MRI Ruby has
concentrated on `Fiber#resume` and `Fiber.yield` for transferring control
between fibers, Polyphony uses `Fiber#transfer` exclusively, which allows
fully symmetric transfer of control between fibers.

## Class Methods

### ::await(\*fibers) → [\*result]

Awaits all given fibers, returning when all fibers have terminated. If one of
the given fibers terminates with an uncaught exception, `::await` will terminate
and await all fibers that are still running, then reraise the exception. All the
given fibers are guaranteed to have terminated when `::await` returns. If no
exception is raised, `::await` returns an array containing the results of all
given fibers, in the same order.

```ruby
f1 = spin { sleep 1 }
f2 = spin { sleep 2 }
Fiber.await(f1, f2)
```

### ::select(\*fibers) → [\*result]

Selects the first fiber to have terminated among the given fibers. If any of the
given fibers terminates with an uncaught exception, `::select` will reraise the
exception. If no exception is raised, `::select` returns an array containing the
fiber and its result. All given fibers are guaranteed to have terminated when
`::select` returns.

```ruby
# get the fastest reply of a bunch of URLs
fibers = urls.map { |u| spin { [u, HTTParty.get(u)] } }
fiber, (url, result) = Fiber.select(*fibers)
```

## Instance methods

### #&lt;&lt;(object) → fiber<br>#send(object) → fiber

Adds a message to the fiber's mailbox. The message can be any object. This
method is complemented by `Fiber#receive`.

```ruby
f = spin do
  loop do
    receiver, x = receive
    receiver << x * 10
  end
end
f << 2
result = receive #=> 20
```

### #auto_watcher → async

Returns a reusable `Gyro::Async` watcher instance associated with the fiber.
This method provides a way to minimize watcher allocation. Instead of allocating
a new async watcher every time one is needed, the same watcher associated with
the fiber is reused.

```ruby
def work(async)
  do_something
  async.signal
end

async = Fiber.current.auto_watcher
spin { work(async) }
async.await
```

### #await → object<br>#join → object

Awaits the termination of the fiber. If the fiber terminates with an uncaught
exception, `#await` will reraise the exception. Otherwise `#await` returns the
result of the fiber.

```ruby
f = spin { 'foo' }
f.await #=> 'foo'
```

### #await_all_children → fiber

Waits for all the fiber's child fibers to terminate. This method is normally
coupled with `Fiber#terminate_all_children`. See also
`Fiber#shutdown_all_children`.

```ruby
jobs.each { |j| spin { process(j) } }
sleep 1
terminate_all_children
await_all_children
```

### #caller → [*location]

Return the execution stack of the fiber, including that of the fiber from which
it was spun.

```ruby
spin {
  spin {
    spin {
      pp Fiber.current.caller
    }.await
  }.await
}.await

#=> ["examples/core/xx-caller.rb:3:in `block (2 levels) in <main>'",
#=>  "examples/core/xx-caller.rb:2:in `block in <main>'",
#=>  "examples/core/xx-caller.rb:1:in `<main>'"]
```

### #cancel! → fiber

Terminates the fiber by raising a `Polyphony::Cancel` exception. If uncaught,
the exception will be propagated.

```ruby
f = spin { sleep 1 }
f.cancel! #=> exception: Polyphony::Cancel
```

### #children → [\*fiber]

Returns an array containing all of the fiber's child fibers. A child fiber's
lifetime is limited to that of its immediate parent.

```ruby
f1 = spin { sleep 1 }
f2 = spin { sleep 1 }
f3 = spin { sleep 1 }
Fiber.current.children #=> [f1, f2, f3]
```

### #interrupt(object = nil) → fiber<br>#stop(object = nil) → fiber

Terminates the fiber by raising a `Polyphony::MoveOn` exception in its context.
The given object will be set as the fiber's result. Note that a `MoveOn`
exception is never propagated.

```ruby
f = spin { do_something_slow }
f.interrupt('never mind')
f.await #=> 'never mind'
```

### #location → string

Returns the location of the fiber's associated block, or `(root)` for the main
fiber.

### #main? → true or false

Returns true if the fiber is the main fiber for its thread.

### #parent → fiber

Returns the fiber's parent fiber. The main fiber's parent is nil.

```ruby
f = spin { sleep 1 }
f.parent #=> Fiber.current
```

### #raise(\*args) → fiber

Raises an error in the context of the fiber. The given exception can be a string
(for raising `RuntimeError` exceptions with a given message), an exception
class, or an exception instance. If no argument is given, a `RuntimeError` will
be raised. Uncaught exceptions will be propagated.

```ruby
f = spin { sleep 1 }
f.raise('foo') # raises a RuntimeError
f.raise(MyException, 'my error message') # exception class with message
f.raise(MyException.new('my error message')) # exception instance
# or simply
f.raise
```

### #receive → object

Pops the first message from the fiber's mailbox. If no message is available,
`#receive` will block until a message is pushed to the mailbox. The received
message can be any kind of object. This method is complemented by
`Fiber#<<`/`Fiber#send`.

```ruby
spin { Fiber.current.parent << 'hello from child' }
message = receive #=> 'hello from child'
```

### #receive_all_pending → [*object]

Returns all messages currently in the mailbox, emptying the mailbox. This method
does not block if no the mailbox is already empty. This method may be used to
process any pending messages upon fiber termination:

```ruby
worker = spin do
  loop do
    job = receive
    handle_job(job)
  end
rescue Polyphony::Terminate => e
  receive_all_pending.each { |job| handle_job(job) }
end
```

### #restart(object = nil) → fiber<br>#reset(object = nil) → fiber

Restarts the fiber, essentially rerunning the fiber's associated block,
restoring it to its primary state. If the fiber is already terminated, a new
fiber will be created and returned. If the fiber's block takes an argument, its
value can be set by passing it to `#restart`.

```ruby
counter = 0
f = spin { sleep 1; counter += 1 }
f.await #=> 1
f.restart
f.await #=> 2
```

### #result → object

Returns the result of the fiber. If the fiber has not yet terminated, `nil` is
returned. If the fiber terminated with an uncaught exception, the exception is
returned.

```ruby
f = spin { sleep 1; 'foo' }
f.await
f.result #=> 'foo'
```

### #running? → true or false

Returns true if the fiber is not yet terminated.

### #schedule(object = nil) → fiber

Adds the fiber to its thread's run queue. The fiber will be eventually resumed
with the given value, which can be any object. If an exception is given, it will
be raised in the context of the fiber upon resuming. If the fiber is already on
the run queue, the resume value will be updated.

```ruby
f = spin do
  result = suspend
  p result
end

sleep 0.1
f.schedule 'foo'
f.await
#=> 'foo'
```

### #shutdown_all_children → fiber

Terminates all of the fiber's child fibers and blocks until all are terminated.
This method is can be used to replace calls to `#terminate_all_children`
followed by `#await_all_children`.

```ruby
jobs.each { |j| spin { process(j) } }
sleep 1
shutdown_all_children
```

### #spin(tag = nil, { block }) → fiber

Creates a new fiber with self as its parent. The returned fiber is put on the
run queue of the parent fiber's associated thread. A tag of any object type can
be associated with the fiber. Note that `Object#spin` is a shortcut for
`Fiber.current.spin`.

```ruby
f = Fiber.current.spin { |x|'foo' }
f.await #=> 'foo'
```

If the block takes an argument, its value can be controlled by explicitly
calling `Fiber#schedule`. The result of the given block (the value of the last
statement in the block) can be retrieved using `Fiber#result` or by otherwise
using fiber control APIs such as `Fiber#await`.

```ruby
f = spin { |x| x * 10 }
f.schedule(2)
f.await #=> 20
```

### #state → symbol

Returns the fiber's current state, which can be any of the following:

- `:waiting` - the fiber is currently waiting for an operation to complete.
- `:runnable` - the fiber is scheduled to be resumed (put on the run queue).
- `:running` - the fiber is currently running.
- `:dead` - the fiber has terminated.

### #supervise(opts = {}) → fiber

Supervises all child fibers, optionally restarting any fiber that terminates.

The given `opts` argument controls the behaviour of the supervision. The
following options are currently supported:

- `:restart`: restart options
  - `nil` - Child fibers are not restarted (default behaviour).
  - `true` - Any child fiber that terminates is restarted.
  - `:on_error` - Any child fiber that terminates with an uncaught exception is
    restarted.
- `:watcher`: a fiber watching supervision events.

If a watcher fiber is specified, it will receive supervision events to its
mailbox. The events are of the form `[<event_type>, <fiber>]`, for example
`[:restart, child_fiber_1]`. Here's an example of using a watcher fiber:

```ruby
watcher = spin_loop do
  kind, fiber = receive
  case kind
  when :restart
    puts "fiber #{fiber.inspect} restarted"
  end
end
...
supervise(restart: true, watcher: watcher)
```

### #tag → object

Returns the tag associated with the fiber, normally passed to `Fiber#spin`. The
tag can be any kind of object. The default tag is `nil`.

```ruby
f = spin(:worker) { do_some_work }
f.tag #=> :worker
```

### #tag=(object) → object

Sets the tag associated with the fiber. The tag can be any kind of object.

```ruby
f = spin { do_some_work }
f.tag = :worker
```

### #terminate → fiber

Terminates the fiber by raising a `Polyphony::Terminate` exception. The
exception is not propagated. Note that the fiber is not guaranteed to terminate
before `#terminate` returns. The fiber will need to run first in order to raise
the `Terminate` exception and terminate. This method is normally coupled with
`Fiber#await`:

```ruby
f1 = spin { sleep 1 }
f2 = spin { sleep 2 }

f1.await

f2.terminate
f2.await
```

### #terminate_all_children → fiber

Terminates all of the fiber's child fibers. Note that `#terminate_all_children`
does not acutally wait for all child fibers to terminate. This method is
normally coupled with `Fiber#await_all_children`. See also `Fiber#shutdown_all_children`.

```ruby
jobs.each { |j| spin { process(j) } }
sleep 1
terminate_all_children
await_all_children
```

### #thread → thread

Returns the thread to which the fiber belongs.

```ruby
f = spin(:worker) { do_some_work }
f.thread #=> Thread.current
```

### #when_done({ block }) → fiber

Installs a hook to be called when the fiber is terminated. The block will be
called with the fiber's result. If the fiber terminates with an uncaught
exception, the exception will be passed to the block.

```ruby
f = spin { 'foo' }
f.when_done { |r| puts "got #{r} from fiber" }
f.await #=> STDOUT: 'got foo from fiber'
```
