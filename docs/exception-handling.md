# @title Exception Handling

# Exception Handling

Ruby employs a pretty robust exception handling mechanism. An raised exception
will propagate up the fiber tree until a suitable exception handler is found,
based on the exception's class. In addition, the exception will include a stack
trace showing the execution path from the exception's locus back to the
program's entry point. Unfortunately, when exceptions are raised while switching
between fibers, stack traces will only include partial information. Here's a
simple demonstration:

_fiber\_exception.rb_

```ruby
require 'fiber'

def fail!
  raise 'foobar'
end

f = Fiber.new do
  Fiber.new do
    fail!
  end.transfer
end

f.transfer
```

Running the above program will give us:

```text
Traceback (most recent call last):
        1: from fiber_exception.rb:9:in `block (2 levels) in <main>'
fiber_exception.rb:4:in `fail!': foobar (RuntimeError)
```

So, the stack trace includes two frames: the exception's locus on line 4 and the
call site at line 9. But we have no information on how we got to line 9. Let's
imagine if we had more complete information about the sequence of execution. In
fact, what is missing is information about how the different fibers were
created. If we had that, our stack trace would have looked something like this:

```text
Traceback (most recent call last):
        4: from fiber_exception.rb:13:in `<main>'
        3: from fiber_exception.rb:7:in `Fiber.new'
        2: from fiber_exception.rb:8:in `Fiber.new'
        1: from fiber_exception.rb:9:in `block (2 levels) in <main>'
fiber_exception.rb:4:in `fail!': foobar (RuntimeError)
```

In order to achieve this, Polyphony patches `Fiber.new` to keep track of the
call stack at the moment the fiber was created, as well as the fiber from which
the call happened. In addition, Polyphony patches `Exception#backtrace` in order
to synthesize a complete stack trace based on the call stack information stored
for the current fiber. This is done recursively through the chain of fibers
leading up to the current location. What we end up with is a record of the
entire sequence of \(possibly intermittent\) execution leading up to the point
where the exception was raised.

In addition, the backtrace is sanitized to remove stack frames originating from
the Polyphony code itself, which hides away the Polyphony plumbing and lets
developers concentrate on their own code. The sanitizing of exception backtraces
can be disabled by setting the `Exception.__disable_sanitized_backtrace__` flag:

```ruby
Exception.__disable_sanitized_backtrace__ = true
...
```

## Exceptions and Fiber Scheduling

Polyphony takes advantages of Ruby's `Fiber#transfer` API to allow interrupting
fiber execution and raise cross-fiber exceptions. This is done by inspecting the
return value of `Fiber#transfer`, which returns when the fiber resumes, at every
[switchpoint](../fiber-scheduling/#switchpoints). If the return value is an
exception, it is raised in the context of the resumed fiber, and is then subject
to any `rescue` statements in the context of that fiber.

Exceptions can be passed to arbitrary fibers by using `Fiber#raise`. They can
also be manually raised in fibers by using `Fiber#schedule`:

```ruby
f = spin do
  suspend
rescue => e
  puts e.message
end

f.schedule(RuntimeError.new('foo')) #=> will print 'foo'
```

## Cleaning Up After Exceptions - Using ensure

A major issue when handling exceptions is cleaning up - freeing up resources
that have been allocated, cancelling ongoing operations, etc. Polyphony allows
using the normal `ensure` statement for cleaning up. Have a look at Polyphony's
implementation of `Kernel#sleep`:

```ruby
def sleep(duration)
  timer = Gyro::Timer.new(duration, 0)
  timer.await
ensure
  timer.stop
end
```

This method creates a one-shot timer with the given duration and then suspends
the current fiber, waiting for the timer to fire and then resume the fiber.
While the awaiting fiber is suspended, other operations might be going on, which
might interrupt the `sleep` operation by scheduling the awaiting fiber with an
exception, for example a `MoveOn` or a `Cancel` exception. For this reason, we
need to _ensure_ that the timer will be stopped, regardless of whether it has
fired or not. We call `timer.stop` inside an ensure block, thus ensuring that
the timer will have stopped once the awaiting fiber has resumed, even if it has
not fired.

## Exception Propagation

One of the "annoying" things about exceptions is that for them to be useful, you
have to intercept them \(using `rescue`\). If you forget to do that, you'll end
up with uncaught exceptions that can wreak havoc. For example, by default a Ruby
`Thread` in which an exception was raised without being caught, will simply
terminate with the exception silently swallowed.

To prevent the same from happening with fibers, Polyphony provides a robust
mechanism that propagates uncaught exceptions up through the chain of parent
fibers. Let's discuss the following example:

```ruby
require 'polyphony'

spin do
  spin do
    spin do
      spin do
        raise 'foo'
      end
      sleep
    end
    sleep
  end
  sleep
end

sleep
```

In the above example, four nested fibers are created, and each of them, except
for the innermost fiber, goes to sleep for an unlimited duration. An exception
is raised in the innermost fiber, and having no corresponding exception handler,
will propagate up through the enclosing fibers, until reaching the
top-most level, that of the root fiber, at which point the exception will cause
the program to abort and print an error message.

## MoveOn and Cancel - Interrupting Fiber Execution

In addition to enhancing Ruby's normal exception-handling mechanism, Polyphony
provides two exception classes that used exclusively to interrupt fiber
execution: `MoveOn` and `Cancel`. Both of these classes are used in various
fiber-control APIs, and `MoveOn` exceptions in particular are handled in a
particular manner by Polyphony. The difference between `MoveOn` and `Cancel` is
that `MoveOn` stops fiber execution without the exception propagating. It can
optionally provide an arbitrary return value for the fiber. `Cancel` will propagate
up like all exceptions.

The `MoveOn` and `Cancel` classes are normally used indirectly, through the
`Fiber#interrupt` and `Fiber#cancel` APIs, and also through the use of [cancel
scopes](#):

```ruby
f1 = spin { sleep 100; return 'foo' }
f2 = spin { f1.await }
...
f1.interrupt('bar')
f2.result #=> 'bar'

f3 = spin { sleep 100 }
...
f3.cancel #=> will raise a Cancel exception
```

In addition to `MoveOn` and `Cancel`, Polyphony employs internally another
exception class, `Terminate` for terminating a fiber once its parent has
finished executing.

## The Special Problem of Signal Handling

In Ruby, signals are handled using `Kernel#trap`, which installs a signal
handler. The problem with signal handlers is that they can be run at any moment,
interrupting whatever work your program is busy with. In order to make signal
handling play nice with the constraints of structured concurrency and the
propagation of exceptions, Polyphony performs signal handling asynchronously.

When a signal is intercepted, instead of running the signal handler immediately,
Polyphony creates a special-purpose fiber that will run the signal handling
code. This fiber is added to the top of the main thread's runqueue. When the
currently running fiber yields control, the special signal handling fiber will
be the next to run. Consequently, signal handlers in Polyphony can perform any
action, from file I/O, printing stuff to STDOUT, or simply raising an
exception.

Two signals in particular require special care as they involve the stopping of
the entire process: `TERM` and `INT`. The `TERM` signal should be handled
gracefully, i.e. with proper cleanup, which also means terminating all fibers.
The `INT` signal requires halting the process and printing a correct stack
trace.

To ensure correct behaviour for these two signals, polyphony installs signal
handlers that ensure that the main thread's event loop stops if it's currently
running, and that the corresponding exceptions (namely `SystemExit` and
`Interrupt`) are handled correctly by passing them to the main fiber.

### Graceful process termination

In order to ensure your application terminates gracefully upon receiving an
`INT` or `TERM` signal, you'll need to rescue the corresponding exceptions in
the main fiber:

```ruby
# In a worker fiber
def do_work
  loop do
    req = receive
    handle_req(req)
  end
rescue Polyphony::Terminate
  # We still need to handle any pending request
  receive_all_pending.each { handle_req(req) }
end

# on the main fiber
begin
  spin_up_lots_fibers
rescue Interrupt, SystemExit
  Fiber.current.terminate_all_children
  Fiber.current.await_all_children
end
```

## The Special Problem of Thread Termination

Thread termination using `Thread#kill` or `Thread#raise` also presents the same
problems as signal handling in a multi-fiber environment. The termination can
occur while any fiber is running, and even while running the thread's event
loop.

To ensure proper thread termination, including the termination of all the
thread's fibers, Polyphony patches the `Thread#kill` and `Thread#raise` methods
to schedule the thread's main fiber with the corresponding exceptions, thus
ensuring an orderly termination or exception handling.
