# Rubato - Fiber-Based Concurrency for Ruby

[INSTALL](#installing-rubato) |
[OVERVIEW](#how-rubato-works---a-technical-overview) |
[EXAMPLES](examples) |
[REFERENCE](#api-reference) |
[EXTENDING](#extending-rubato)

**Note**: Rubato is still in alpha and is not ready for production use.

> Rubato | rʊˈbɑːtəʊ | *Music* - the temporary disregarding of strict tempo to
> allow an expressive quickening or slackening, usually without altering the
> overall pace.

### Installing Rubato

```bash
$ gem install rubato
```

Rubato is a library for building concurrent applications in Ruby. Rubato
harnesses the power of
[Ruby fibers](https://ruby-doc.org/core-2.5.1/Fiber.html) to provide a
cooperative, sequential coroutine-based concurrency model. Under the hood,
Rubato uses [libev](https://github.com/enki/libev) as a high-performance event
reactor that provides timers, I/O watchers and other asynchronous event
primitives.

Rubato makes it possible to use normal Ruby built-in classes like `IO`,
and `Socket` in a concurrent fashion without having to resort to threads.
Rubato takes care of context-switching automatically whenever a blocking call
like `Socket#accept` or `IO#read` is issued.

## Features

- Co-operative scheduling of concurrent tasks using Ruby fibers.
- High-performance event reactor for handling I/O events and timers.
- Constructs for controlling the execution of concurrent code, including
  supervision and cancellation of concurrent tasks.
- Uses native I/O classes, growing support for gems such as `pg` and `redis`.
- Comprehensive HTTP 1 and HTTP 2 client and server.

## An echo server in Rubato

Here's a bare-bones echo server written using Rubato:

```ruby
require 'rubato'

# spawn starts a new coroutine on a separate thread
spawn {
  server = TCPServer.open(1234)
  while client = server.accept
    spawn {
      while data = client.read rescue nil
        client.write(data)
      end
    }
  end
}
```

This example demonstrates several features of Rubato:

- The code uses `TCPServer`, a class from Ruby's stdlib, to setup a TCP server.
  The result of `server.accept` is also There are no wrapper classes being used.
- The only hint of the code being concurrent is the use of `Kernel.spawn`,
  which starts a new coroutine on a dedicated fiber. This allows serving
  multiple clients at once. Whenever a blocking call is issued, such as
  `#accept` or `#read`, execution is *yielded* to the event loop, which will
  resume only those coroutines which are ready to be resumed.
- Exception handling is done using the normal Ruby constructs `raise`, `rescue`
  and `ensure`. Exceptions never go unhandled (as might be the case with Ruby
  threads), and must be dealt with explicitly. An unhandled exception will
  always cause the Ruby process to exit.

## How Rubato Works - a Technical Overview

### Fiber-based concurrency

The built-in `Fiber` class provides a very elegant foundation for implementing
cooperative, light-weight concurrency (it can also be used for other stuff
like generators). Fiber-based concurrency can be considered as the
[*third way*](https://en.wikipedia.org/wiki/Fiber_(computer_science))
of writing concurrent programs (the other two being multi-process concurrency
and multi-thread concurrency), and can provide very good performance
characteristics for I/O-bound applications.

In contrast to callback-based concurrency (e.g. Node.js or EventMachine),
fibers allow writing concurrent code in a sequential manner without having to
split your logic into different locations, or submitting to
[callback hell](http://callbackhell.com/).

Rubato builds on the foundation of Ruby fibers in order to facilitate writing
high-performance I/O-bound applications in Ruby.

### Context-switching on blocking calls

Ruby monkey-patches existing methods such as `IO#read` to setup an IO watcher
and suspend the current fiber until the IO object is ready to be read. Once
the IO watcher is signalled, the associated fiber is resumed and the method
call can continue. Here's a simplified implementation of
[`IO#read`](lib/rubato/io.rb#24-36):

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
    Fiber.yield
  end
end
```

### Running a high-performance event loop

Rubato  runs a libev-based event loop that watches events such as IO-readiness,
elapsed timers, received signals and other asynchronous happenings, and uses
them to control fiber execution. The magic continues the IO watcher is
[signalled](ext/ev/io.c#110-127): the fiber associated with the watcher is
resumed, and control is given back to the calling method. Here's a naïve
implementation:

```ruby
class IOWatcher
  def fire
    @fiber.resume
  end
end
```

### Additional concurrency constructs

In order to facilitate writing concurrent code, Rubato provides additional
constructs that make it easier to spawn concurrent tasks and to control them.

`Coroutine` - a class encapsulating a task running on a dedicated fiber. A
coroutine can be short- or long-lived. It can be suspended and resumed, awaited
and cancelled. It is usually started using `Kernel.spawn`:

```ruby
10.times do
  spawn {
    sleep 1
    puts "done sleeping"
  }
end
```

`Supervisor` - a class used to control one or more `Coroutine`s. It can be used
to start, stop and restart multiple coroutines. A supervisor can also be
used for awaiting the completion of multiple coroutines. It is usually started
using `Kernel.supervise`:

```ruby
spawn {
  supervise { |s|
    s.spawn { sleep 1 }
    s.spawn { sleep 2 }
    s.spawn { sleep 3 }
  }
  puts "done sleeping"
}
```

`CancelScope` - an abstraction used to cancel the execution of one or more
coroutines or supervisors. It usually works by defining a timeout for the 
completion of a task. Any blocking operation can be cancelled, including
a coroutine or a supervisor. The developer may choose to cancel with or without
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

`ThreadPool` - a pool of threads used to run any operation that cannot be
implemented using non-blocking calls, such as file system calls. The operation
is offloaded to a worker thread, allowing the event loop to continue processing
other tasks. For example, `IO.read` and `File.stat` are both reimplemented
using the Rubato thread pool. You can easily use the thread pool to run your
own blocking operations as follows:

```ruby
result = Rubato::ThreadPool.process { long_running_process }
```

### Prior Art

Rubato draws inspiration from the following, in no particular order:

* [nio4r](https://github.com/socketry/nio4r/)
* [EventMachine](https://github.com/eventmachine/eventmachine)
* [Trio](https://trio.readthedocs.io/)
* [Erlang supervisors](http://erlang.org/doc/man/supervisor.html)

## API Reference

To be continued...

## Extending Rubato

Rubato was designed to ease the transition from blocking APIs and
callback-based API to non-blocking, fiber-based ones. It is important to
understand that not all blocking calls can be easily converted into
non-blocking calls. That might be the case with Ruby gems based on
C-extensions, such as database libraries. In that case, Rubato's built-in
[thread pool](#threadpool) might be used for offloading such blocking calls.

### Adapting callback-based APIs

Some of the most common patterns in Ruby APIs is the callback pattern, in which
the API takes a block as a callback to be called upon completion of a task. One
such example can be found in the excellent
[http_parser.rb](https://github.com/tmm1/http_parser.rb/) gem, which is used by
Rubato itself to provide HTTP 1 functionality. The `HTTP:Parser` provides 
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

A program using `http_parser.rb` in conjunction with Rubato might do the
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

### Contributing to Rubato

If there's some blocking behavior you'd like to see handled by Rubato, please
let us know by
[creating an issue](https://github.com/digital-fabric/rubato/issues). Our aim
is for Rubato to be a comprehensive solution for writing concurrent Ruby
programs.