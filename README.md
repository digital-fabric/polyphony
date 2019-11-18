# Polyphony - lightweight concurrency for Ruby

[INSTALL](#installing-polyphony) |
[TUTORIAL](#getting-started) |
[EXAMPLES](examples) |
[TEHNICAL OVERVIEW](#how-polyphony-works---a-technical-overview) |
[REFERENCE](#api-reference) |
[EXTENDING](#extending-polyphony)

> Polyphony | pəˈlɪf(ə)ni | *Music* - the style of simultaneously combining a
> number of parts, each forming an individual melody and harmonizing with each
> other.

**Note**: Polyphony is experimental software. It is designed to work with recent
versions of Ruby (2.5 and newer) and supports Linux and MacOS only.

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

- **Full-blown, integrated, high-performance HTTP 1 / HTTP 2 / WebSocket server
  with TLS/SSL termination, automatic ALPN protocol selection, and body
  streaming**.
- Co-operative scheduling of concurrent tasks using Ruby fibers.
- High-performance event reactor for handling I/O events and timers.
- Natural, sequential programming style that makes it easy to reason about
  concurrent code.
- Abstractions and constructs for controlling the execution of concurrent code:
  coprocesses, supervisors, cancel scopes, throttling, resource pools etc.
- Code can use native networking classes and libraries, growing support for
  third-party gems such as `pg` and `redis`.
- HTTP 1 / HTTP 2 client agent with persistent connections.
- Competitive performance and scalability characteristics, in terms of both
  throughput and memory consumption.

## Why you should not use Polyphony

- Polyphony does weird things to Ruby, like patching methods like `IO.read`,
  `Kernel#sleep`, and `Timeout.timeout` so they'll work concurrently without
  using threads.
- Error backtraces might look weird.
- There's currently no support for threads - any IO operations in threads will
  likely cause a bad crash.
- Debugging might be confusing or not work at all.
- The API is currently unstable.

## Prior Art

Polyphony draws inspiration from the following, in no particular order:

* [nio4r](https://github.com/socketry/nio4r/) and [async](https://github.com/socketry/async)
  (Polyphony's C-extension code is largely a spinoff of
  [nio4r's](https://github.com/socketry/nio4r/tree/master/ext))
* [EventMachine](https://github.com/eventmachine/eventmachine)
* [Trio](https://trio.readthedocs.io/)
* [Erlang supervisors](http://erlang.org/doc/man/supervisor.html) (and actually,
  Erlang in general)

## Installing Polyphony

```bash
$ gem install polyphony
```

Or add it to your Gemfile, you know the drill.

## Getting Started

Polyphony is designed to help you write high-performance, concurrent code in
Ruby, without using threads. It does so by turning every call which might block,
such as `Kernel#sleep` or `IO#read` into a concurrent operation, which yields
control to an event reactor. The reactor, in turn, may schedule other operations
once they can be resumed. In that manner, multiple ongoing operations may be
processed concurrently.

The simplest way to start a concurrent operation is using `Kernel#spin`:

```ruby
require 'polyphony'

spin do
  puts "A going to sleep"
  sleep 1
  puts "A woken up"
end

spin do
  puts "B going to sleep"
  sleep 1
  puts "B woken up"
end
```

In the above example, both `sleep` calls will be executed concurrently, and thus
the program will take approximately only 1 second to execute. Note how the logic
flow inside each `spin` block is purely sequential, and how the concurrent
nature of the two blocks is expressed simply and cleanly.

## Coprocesses - Polyphony's basic unit of concurrency

In Polyphony, concurrent operations take place inside coprocesses. A `Coprocess`
is executed on top of a `Fiber`, which allows it to be suspended whenever a
blocking operation is called, and resumed once that operation has been
completed. Coprocesses offer significant advantages over threads - they consume
only about 10KB, switching between them is much faster than switching threads,
and literally millions of them can be spinned off without affecting
performance*. Besides, Ruby does not yet allow parallel execution of threads
(courtesy of the Ruby GVL).

\* *This is a totally unsubstantiated claim and has not been proven in practice*.

## An echo server in Polyphony

Let's now examine how networking is done using Polyphony. Here's a bare-bones
echo server written using Polyphony:

```ruby
require 'polyphony'

server = TCPServer.open(1234)
while client = server.accept
  spin do
    while (data = client.gets)
      client << data
    end
  end
end
```

This example demonstrates several features of Polyphony:

- The code uses the native `TCPServer` class from Ruby's stdlib, to setup a TCP
  server. The result of `server.accept` is also a native `TCPSocket` object.
  There are no wrapper classes being used.
- The only hint of the code being concurrent is the use of `Kernel#spin`,
  which starts a new coprocess on a dedicated fiber. This allows serving
  multiple clients at once. Whenever a blocking call is issued, such as
  `#accept` or `#read`, execution is *yielded* to the event reactor loop, which 
  will resume only those coprocesses which are ready to be resumed.
- Exception handling is done using the normal Ruby constructs `raise`, `rescue`
  and `ensure`. Exceptions never go unhandled (as might be the case with Ruby
  threads), and must be dealt with explicitly. An unhandled exception will by
  default cause the Ruby process to exit.

## Additional concurrency constructs

In order to facilitate writing concurrent code, Polyphony provides additional
mechanisms that make it easier to create and control concurrent tasks.

### Cancel scopes

Cancel scopes, an idea borrowed from Python's
[Trio](https://trio.readthedocs.io/) library, are used to cancel the execution
of one or more coprocesses. The most common use of cancel scopes is a for 
implementing a timeout for the completion of a task. Any blocking operation can
be cancelled. The programmer may choose to raise a `Cancel` exception when an
operation has been cancelled, or alternatively to move on without any exception.

Cancel scopes are typically started using `Kernel#cancel_after` and 
`Kernel#move_on_after` for cancelling with or without an exception,
respectively. Cancel scopes will take a block of code to execute and run it, 
providing a reference to the cancel scope:

```ruby
puts "going to sleep (but really only for 1 second)..."
cancel_after(1) do
  sleep(60)
end
```

Patterns like closing a connection after X seconds of activity are greatly
facilitated by timeout-based cancel scopes, which can be easily reset:

```ruby
def echoer(client)
  # close connection after 10 seconds of inactivity
  move_on_after(10) do |scope|
    scope.when_cancelled { puts "closing connection due to inactivity" }
    loop do
      data = client.read
      scope.reset_timeout
      client.write
    end
  end
  client.close
end
```

Cancel scopes may also be manually cancelled by calling `CancelScope#cancel!`
at any time:

```ruby
def echoer(client)
  move_on_after(60) do |scope|
    loop do
      data = client.read
      scope.cancel! if data == 'stop'
      client.write
    end
  end
  client.close
end
```

### Resource pools

A resource pool is used to control access to one or more shared, usually
identical resources. For example, a resource pool can be used to control
concurrent access to database connections, or to limit concurrent
requests to an external API:

```ruby
# up to 5 concurrent connections
Pool = Polyphony::ResourcePool.new(limit: 5) {
  # the block sets up the resource
  PG.connect(...)
}

1000.times {
  spin {
    Pool.acquire { |db| p db.query('select 1') }
  }
}
```

You can also call arbitrary methods on the resource pool, which will be
delegated to the resource using `#method_missing`:

```ruby
# up to 5 concurrent connections
Pool = Polyphony::ResourcePool.new(limit: 5) {
  # the block sets up the resource
  PG.connect(...)
}

1000.times {
  spin { p Pool.query('select pg_sleep(0.01);') }
}
```

### Supervisors

A supervisor is used to control one or more coprocesses. It can be used to
start, stop, restart and await the completion of multiple coprocesses. It is 
normally started using `Kernel#supervise`:

```ruby
supervise { |s|
  s.spin { sleep 1 }
  s.spin { sleep 2 }
  s.spin { sleep 3 }
}
puts "done sleeping"
```

The `Kernel#supervise` method will await the completion of all supervised 
coprocesses. If any supervised coprocess raises an error, the supervisor will
automatically cancel all other supervised coprocesses.

### Throttlers

A throttler is a mechanism for controlling the speed of an arbitrary task,
such as sending of emails, or crawling a website. A throttler is normally
created using `Kernel#throttle` or `Kernel#throttled_loop`, and can even be used 
to throttle operations across multiple coprocesses:

```ruby
server = Polyphony::Net.tcp_listen(1234)

# a shared throttler, up to 10 times per second
throttler = throttle(rate: 10)

while client = server.accept
  spin do
    throttler.call do
      while data = client.read
        client.write(data)
      end
    end
  end
end
```

`Kernel#throttled_loop` can be used to run throttled infinite loops:

```ruby
throttled_loop(3) do
  STDOUT << '.'
end
```

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

> **Running a high-performance event loop**: Polyphony runs a libev-based event
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
require 'polyphony'

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