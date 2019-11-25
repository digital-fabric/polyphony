# Exception Handling in a Multi-Fiber Environment

Ruby employs a pretty robust exception handling mechanism. An raised exception
will bubble up the call stack until a suitable exception handler is found, based
on the exception's class. In addition, the exception will include a stack trace
showing the execution path from the exception's locus back to the program's
entry point. Unfortunately, when exceptions are raised while switching between
fibers, stack traces will only include partial information. Here's a simple
demonstration:

*fiber_exception.rb*
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

```
Traceback (most recent call last):
        1: from fiber_exception.rb:9:in `block (2 levels) in <main>'
fiber_exception.rb:4:in `fail!': foobar (RuntimeError)
```

So, the stack trace includes two frames: the exception's locus on line 4 and the
call site at line 9. But we have no information on how we got to line 9. Let's
imagine if we had more complete information about the sequence of execution. In
fact, what is missing is information about how the different fibers were
created. If we had that, our stack trace would have looked something like this:

```
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
entire sequence of (possibly intermittent) execution leading up to the point
where the exception was raised.

In addition, the backtrace is sanitized to remove stack frames originating from
the Polyphony code itself, which hides away the Polyphony plumbing and lets
developers concentrate on their own code. The sanitizing of exception backtraces
can be disabled by setting the `Exception.__disable_sanitized_backtrace__` flag:

```ruby
Exception.__disable_sanitized_backtrace__ = true
...
```