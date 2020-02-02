---
layout: page
title: Exception Handling
nav_order: 4
parent: Technical Overview
permalink: /technical-overview/exception-handling/
prev_title: How Fibers are Scheduled
next_title: Extending Polyphony
---
# Exception Handling

Ruby employs a pretty robust exception handling mechanism. An raised exception
will bubble up the call stack until a suitable exception handler is found, based
on the exception's class. In addition, the exception will include a stack trace
showing the execution path from the exception's locus back to the program's
entry point. Unfortunately, when exceptions are raised while switching between
fibers, stack traces will only include partial information. Here's a simple
demonstration:

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

Exceptions can be passed to arbitrary fibers by using `Fiber#raise`. They can also be manually raised in fibers by using `Fiber#schedule`:

```ruby
f = spin do
  suspend
rescue => e
  puts e.message
end

f.schedule(RuntimeError.new('foo')) #=> will print 'foo'
```

## Cleaning Up After Exceptions - Using Ensure

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

## Bubbling Up - A Robust Solution for Uncaught Exceptions

One of the "annoying" things about exceptions is that for them to be useful, you
have to intercept them \(using `rescue`\). If you forget to do that, you'll end
up with uncaught exceptions that can wreak havoc. For example, by default a Ruby
`Thread` in which an exception was raised without being caught, will simply
terminate with the exception silently swallowed.

To prevent the same from happening with fibers, Polyphony provides a mechanism
that lets uncaught exceptions bubble up through the chain of calling fibers.
Let's discuss the following example:

```ruby
require 'polyphony'

spin do
  spin do
    spin do
      spin do
        raise 'foo'
      end.await
    end.await
  end.await
end.await
```

In this example, there are four fibers, nested one within the other. An
exception is raised in the inner most fiber, and having no exception handler,
will bubble up through the different enclosing fibers, until reaching the
top-most level, that of the root fiber, at which point the exception will cause
the program to halt and print an error message.

## MoveOn and Cancel - Interrupting Fiber Execution

In addition to enhancing Ruby's normal exception-handling mechanism, Polyphony
provides two exception classes that used exclusively to interrupt fiber
execution: `MoveOn` and `Cancel`. Both of these classes are used in various
fiber-control APIs, and `MoveOn` exceptions in particular are handled in a
particular manner by Polyphony. The difference between `MoveOn` and `Cancel` is
that `MoveOn` stops fiber execution without the exception bubbling up. It can
optionally provide an arbitrary return value for the fiber. `Cancel` will bubble
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

## Signal Handling and Termination

Polyphony does not normally intercept process signals, though it is possible to
intercept them using `Gyro::Signal` watchers. It is, however, recommended for
the time being to not interfere with Ruby's normal signal processing.

In Ruby there are three core exception classes are related to signal handling
and process termination: `Interrupt` - raised upon receiving an `INT` signal;
`SystemExit` - raised upon calling `Kernel#exit`; and `SignalException` - raised
upon receiving other signals.

These exceptions are raised on the main thread and in a multi-fiber environment
can occur in any fiber, as long as it is the currently running fiber. In
Polyphony, when these exceptions are raised in a fiber other than the main
fiber, they will be effectively tranferred to the main fiber for processing.

This means that any handlers for these three exception classes should be put
only in the main fiber. This mechanism also helps with showing a correct
backtrace for these exceptions.
