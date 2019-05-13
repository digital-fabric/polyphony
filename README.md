# Polyphony - Fiber-Based Concurrency for Ruby

[INSTALL](#installing-polyphony) |
[TUTORIAL](#getting-started) |
[EXAMPLES](examples) |
[TEHNICAL OVERVIEW](#how-polyphony-works---a-technical-overview) |
[REFERENCE](#api-reference) |
[EXTENDING](#extending-polyphony)

> Polyphony | pəˈlɪf(ə)ni | *Music* - the style of simultaneously combining a
> number of parts, each forming an individual melody and harmonizing with each
> other.

**Note**: Polyphony is designed to work with recent versions of Ruby and
supports Linux and MacOS only. This software is currently at the alpha stage.

## What is Polyphony

Polyphony is a library for building concurrent applications in Ruby. Polyphony
harnesses the power of
[Ruby fibers](https://ruby-doc.org/core-2.5.1/Fiber.html) to provide a
cooperative, sequential coprocess-based concurrency model. Under the hood,
Polyphony uses [libev](https://github.com/enki/libev) as a high-performance event
reactor that provides timers, I/O watchers and other asynchronous event
primitives.

Polyphony makes it possible to use normal Ruby built-in classes like `IO`, and
`Socket` in a concurrent fashion without having to resort to threads. Polyphony
takes care of context-switching automatically whenever a blocking call like
`Socket#accept` or `IO#read` is issued.

## Features

- Co-operative scheduling of concurrent tasks using Ruby fibers.
- High-performance event reactor for handling I/O events and timers.
- Natural, sequential programming style that makes it easy to reason about
  concurrent code.
- Higher-order constructs for controlling the execution of concurrent code:
  coprocesses, supervisors, cancel scopes, throttling, resource pools etc.
- Code can use native networking classes and libraries, growing support for
  third-party gems such as `pg` and `redis`.
- Comprehensive HTTP 1.0 / 1.1 / 2 client and server APIs.
- Excellent performance and scalability characteristics, in terms of both
  throughput and memory consumption.

## Prior Art

Polyphony draws inspiration from the following, in no particular order:

* [nio4r](https://github.com/socketry/nio4r/) and [async](https://github.com/socketry/async)
* [EventMachine](https://github.com/eventmachine/eventmachine)
* [Trio](https://trio.readthedocs.io/)
* [Erlang supervisors](http://erlang.org/doc/man/supervisor.html) (and actually,
  Erlang in general)

## Installing Polyphony

```bash
$ gem install polyphony
```

## Getting Started

Polyphony is designed to help you write high-performance, concurrent code in
Ruby. It does so by turning every call which might block, such as `sleep` or
`read` into a concurrent operation, which yields control to an event reactor.
The reactor, in turn, may schedule other operations once they can be resumed. In
that manner, multiple ongoing operations may be processed concurrently.

There are multiple ways to start a concurrent operation, the most common of
which is `Kernel#spawn`:

```ruby
require 'polyphony'

spawn do
  puts "A going to sleep"
  sleep 1
  puts "A woken up"
end

spawn do
  puts "B going to sleep"
  sleep 1
  puts "B woken up"
end
```

In the above example, both `sleep` calls will be executed concurrently, and thus
the program will take approximately only 1 second to execute. Note the lack of
any boilerplate relating to concurrency. Each `spawn` block starts a
*coprocess*, and is executed in sequential manner.

> **Coprocesses - the basic unit of concurrency**: In Polyphony, concurrent
> operations take place inside coprocesses. A `Coprocess` is executed on top of
> a `Fiber`, which allows it to be suspended whenever a blocking operation is
> called, and resumed once that operation has been completed. Coprocesses offer
> significant advantages over threads - they consume only about 10KB, switching
> between them is much faster than switching threads, and literally millions of
> them can be spawned without affecting performance*. Besides, Ruby does not yet
> allow parallel execution of threads.
> 
> \* *This is a totally unsubstantiated claim which has not been proved in
> practice*.

## An echo server in Polyphony

To take matters further, let's see how networking can be done using Polyphony.
Here's a bare-bones echo server written using Polyphony:

```ruby
require 'polyphony'

server = TCPServer.open(1234)
while client = server.accept
  # spawn starts a new coprocess on a separate fiber
  spawn {
    while data = client.read rescue nil
      client.write(data)
    end
  }
end
```

This example demonstrates several features of Polyphony:

- The code uses the native `TCPServer` class from Ruby's stdlib, to setup a TCP
  server. The result of `server.accept` is also a native `TCPSocket` object.
  There are no wrapper classes being used.
- The only hint of the code being concurrent is the use of `Kernel#spawn`,
  which starts a new coprocess on a dedicated fiber. This allows serving
  multiple clients at once. Whenever a blocking call is issued, such as
  `#accept` or `#read`, execution is *yielded* to the event loop, which will
  resume only those coprocesses which are ready to be resumed.
- Exception handling is done using the normal Ruby constructs `raise`, `rescue`
  and `ensure`. Exceptions never go unhandled (as might be the case with Ruby
  threads), and must be dealt with explicitly. An unhandled exception will cause
  the Ruby process to exit.

## Going further

To learn more about using Polyphony to build concurrent applications, read the
technical overview below, or look at the [included examples](examples). A
thorough reference is forthcoming.

## How Polyphony Works - a Technical Overview

### Fiber-based concurrency

The built-in `Fiber` class provides a very elegant, if low-level, foundation for 
implementing cooperative, light-weight concurrency (it can also be used for other stuff like generators). Fiber or continuation-based concurrency can be 
considered as the
[*third way*](https://en.wikipedia.org/wiki/Fiber_(computer_science))
of writing concurrent programs (the other two being multi-process concurrency
and multi-thread concurrency), and can provide very good performance
characteristics for I/O-bound applications.

In contrast to callback-based concurrency (e.g. Node.js or EventMachine), fibers
allow writing concurrent code in a sequential manner without having to split
your logic into different locations, or submitting to
[callback hell](http://callbackhell.com/).

Polyphony builds on the foundation of Ruby fibers in order to facilitate writing
high-performance I/O-bound applications in Ruby.

### Context-switching on blocking calls

Ruby monkey-patches existing methods such as `sleep` or `IO#read` to setup an
IO watcher and suspend the current fiber until the IO object is ready to be  
read. Once the IO watcher is signalled, the associated fiber is resumed and the 
method call can continue. Here's a simplified implementation of
[`IO#read`](lib/polyphony/io.rb#24-36):

```ruby
class IO
  def read(max = 8192)
    loop do
      result = read_nonblock(max, exception: false)
      case result
      when nil            then raise IOError
      when :wait_readable then read_watcher.await
      else                     return result
      end
    end
  end
end
```

The magic starts in [`IOWatcher#await`](ext/ev/io.c#157-179), where the watcher
is started and the current fiber is suspended (it "yields" in Ruby parlance).
Here's a naïve implementation (the actual implementation is written in C):

```ruby
class IOWatcher
  def await
    @fiber = Fiber.current
    start
    yield_to_reactor_fiber
  end
end
```

> **Running a high-performance event loop**: Polyphony  runs a libev-based event
> loop that watches events such as IO-readiness, elapsed timers, received
> signals and other asynchronous happenings, and uses them to control fiber
> execution. The event loop itself is run on a separate fiber, allowing the main
> fiber as well to perform blocking operations.

When the IO watcher is [signalled](ext/ev/io.c#99-116): the fiber associated 
with the  watcher is resumed, and control is given back to the calling method. 
Here's a naïve implementation:

```ruby
class IOWatcher
  def signal
    @fiber.transfer
  end
end
```

### Additional concurrency constructs

In order to facilitate writing concurrent code, Polyphony provides additional
constructs that make it easier to spawn concurrent tasks and to control them.

`CancelScope` - an abstraction used to cancel the execution of one or more
coprocesses or supervisors. It usually works by defining a timeout for the 
completion of a task. Any blocking operation can be cancelled, including
a coprocess or a supervisor. The developer may choose to cancel with or without
an exception with `cancel` or `move_on`, respectively. Cancel scopes are
typically started using `Kernel.cancel_after` and `Kernel.move_on`:

```ruby
def echoer(client)
  # cancel after 10 seconds if inactivity
  move_on_after(10) { |scope|
    loop {
      data = client.read
      scope.reset_timeout
      client.write
    }
  }
}
```

`ResourcePool` - a class used to control access to shared resources. It can be
used to control concurrent access to database connections, or to limit 
concurrent requests to an external API:

```ruby
# up to 5 concurrent connections
Pool = Polyphony::ResourcePool.new(limit: 5) {
  # the block sets up the resource
  PG.connect(...)
}

1000.times {
  spawn {
    Pool.acquire { |db| p db.query('select 1') }
  }
}
```

`Supervisor` - a class used to control one or more `Coprocess`s. It can be used
to start, stop and restart multiple coprocesses. A supervisor can also be
used for awaiting the completion of multiple coprocesses. It is usually started
using `Kernel.supervise`:

```ruby
supervise { |s|
  s.spawn { sleep 1 }
  s.spawn { sleep 2 }
  s.spawn { sleep 3 }
}
puts "done sleeping"
```

`ThreadPool` - a pool of threads used to run any operation that cannot be
implemented using non-blocking calls, such as file system calls. The operation
is offloaded to a worker thread, allowing the event loop to continue processing
other tasks. For example, `IO.read` and `File.stat` are both reimplemented
using the Polyphony thread pool. You can easily use the thread pool to run your
own blocking operations as follows:

```ruby
result = Polyphony::ThreadPool.process { long_running_process }
```

`Throttler` - a mechanism for throttling an arbitrary task, such as sending of
emails, or crawling a website. A throttler is normally created using 
`Kernel.throttle`, and can even be used to throttle operations across multiple
coprocesses:

```ruby
server = Net.tcp_listen(1234)
throttler = throttle(rate: 10) # up to 10 times per second

while client = server.accept
  spawn {
    throttler.call {
      while data = client.read
        client.write(data)
      end
    }
  }
end
```

## API Reference

To be continued...

## Extending Polyphony

Polyphony was designed to ease the transition from blocking APIs and 
callback-based API to non-blocking, fiber-based ones. It is important to
understand that not all blocking calls can be easily converted into 
non-blocking calls. That might be the case with Ruby gems based on C-extensions,
such as database libraries. In that case, Polyphony's built-in
[thread pool](#threadpool) might be used for offloading such blocking calls.

### Adapting callback-based APIs

Some of the most common patterns in Ruby APIs is the callback pattern, in which
the API takes a block as a callback to be called upon completion of a task. One
such example can be found in the excellent
[http_parser.rb](https://github.com/tmm1/http_parser.rb/) gem, which is used by
Polyphony itself to provide HTTP 1 functionality. The `HTTP:Parser` provides 
multiple hooks, or callbacks, for being notified when an HTTP request is
complete. The typical callback-based setup is as follows:

```ruby
require 'http/parser'
@parser = Http::Parser.new

def on_receive(data)
  @parser < data
end

@parser.on_message_complete do |env|
  process_request(env)
end
```

A program using `http_parser.rb` in conjunction with Polyphony might do the
following:

```ruby
require 'http/parser'
require 'modulation'

def handle_client(client)
  parser = Http::Parser.new
  req = nil
  parser.on_message_complete { |env| req = env }
  loop do
    parser << client.read
    if req
      handle_request(req)
      req = nil
    end
  end
end
```

Another possibility would be to monkey-patch `Http::Parser` in order to
encapsulate the state of the request:

```ruby
class Http::Parser
  def setup
    self.on_message_complete = proc { @request_complete = true }
  end

  def parser(data)
    self << data
    return nil unless @request_complete

    @request_complete = nil
    self
  end
end

def handle_client(client)
  parser = Http::Parser.new
  loop do
    if req == parser.parse(client.read)
      handle_request(req)
    end
  end
end
```

### Contributing to Polyphony

If there's some blocking behavior you'd like to see handled by Polyphony, please
let us know by
[creating an issue](https://github.com/digital-fabric/polyphony/issues). Our aim
is for Polyphony to be a comprehensive solution for writing concurrent Ruby
programs.