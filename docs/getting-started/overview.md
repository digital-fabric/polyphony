---
layout: page
title: Overview
parent: Getting Started
nav_order: 2
---

# Polyphony - an Overview
{: .no_toc }

## Table of contents
{: .no_toc .text-delta }

- TOC
{:toc}

---

## Introduction

Polyphony is a new Ruby library for building concurrent applications in Ruby.
Polyphony provides a comprehensive, structured concurrency model based on Ruby
fibers and using libev as a high-performance event reactor.

Polyphony is designed to maximize developer happiness. It provides a natural and
fluent API for writing concurrent Ruby apps while using the stock Ruby APIs such
as `IO`, `Process`, `Socket`, `OpenSSL` and `Net::HTTP` in a concurrent
multi-fiber environment. In addition, Polyphony offers a solid
exception-handling experience that builds on and enhances Ruby's
exception-handling mechanisms.

Polyphony includes a full-blown HTTP server implementation with integrated
support for HTTP 1 & 2, WebSockets, TLS/SSL termination and more. Polyphony also
provides fiber-aware adapters for connecting to PostgreSQL and Redis servers.
More adapters are being actively developed.

### Features
{: .no_toc }

- Co-operative scheduling of concurrent tasks using Ruby fibers.
- High-performance event reactor for handling I/O, timer, and other events.
- Natural, sequential programming style that makes it easy to reason about
  concurrent code.
- Abstractions and constructs for controlling the execution of concurrent code:
  supervisors, cancel scopes, throttling, resource pools etc.
- Code can use native networking classes and libraries, growing support for
  third-party gems such as pg and redis.
- Use stdlib classes such as TCPServer and TCPSocket and Net::HTTP.
- Impressive performance and scalability characteristics, in terms of both
  throughput and memory consumption (see below)

## Taking Polyphony for a Spin

Polyphony is different from other reactor-based solutions for Ruby in that
there's no need to use special classes for building your app, and there's no
need to setup reactor loops. Everything works the same except you can perform
multiple operations at the same time by creating fibers. In order to start a new
concurrent operation, you simply use `Kernel#spin`, which spins up a new fiber
and schedules it for running:

```ruby
require 'polyphony'

# Kernel#spin returns a Fiber instance
counter = spin do
  count = 1
  loop do
    sleep 1
    puts "count: #{count}"
    count += 1
  end
end

puts "Press return to stop this program"
gets
```

The above program spins up a fiber named `counter`, which counts to infinity.
Meanwhile, the *main* fiber waits for input from the user, and then exits.
Notice how we haven't introduced any custom classes, and how we used stock APIs
such as `Kernel#sleep` and `Kernel#gets`. The only hint that this program is
concurrent is the call to `Kernel#spin`.

Behind the scenes, Polyphony takes care of automatically switching between
fibers, letting each fiber advance at its own pace according to its duties. For
example, when the main fiber calls `gets`, Polyphony starts waiting for data to
come in on `STDIN` and then switches control to the `counter` fiber. When the
`counter` fiber calls `sleep 1`, Polyphony starts a timer, and goes looking for
other work. If no other fiber is ready to run, Polyphony simply waits for at
least one event to occur, and then resumes the corresponding fiber.

## Fibers vs Threads

Most Ruby developers are familiar with threads, but fibers remain a little
explored and little understood concept in the Ruby language. While A thread is
an OS abstraction that is controlled by the OS, a fiber represents an execution
context that can be paused and resumed by the application, and has no
counterpart at the OS level.

When used for writing concurrent programming, fibers offer multiple benefits
over threads. They consume much less RAM than threads, and switching between
them is faster than switching between threads. In addition, since fibers require
no cooperation from the OS, an application can create literally millions of them
given enough RAM. Those advantages make fibers a compelling solution for creating
pervasively concurrent applications, even when using a dynamic high-level "slow"
language such as Ruby.

Ruby programs will only partly benefit from using mutiple threads for processing
work loads (due to the GVL), but fibers are a great match mostly for programs
that are I/O bound (that means spending most of their time talking to the
outside world). A fiber-based web-server, for example, can juggle thousands of
active concurrent connections, each advancing at its own pace, consuming only a
single CPU core.

Nevertheless, Polyphony fully supports multithreading, with each thread having
its own fiber run queue and its own libev event loop. Polyphony even enables
cross-thread communication using [fiber messaging](#message-passing).

## Fibers vs Callbacks

Programming environments such as Node.js and libraries such as EventMachine have
popularized the usage of event loops for achieving concurrency. The application
is wrapped in a loop that polls for events and fires application-provided
callbacks that act on those events - for example receiving data on a socket
connection, or waiting for a timer to elapse.

While these callback-based solutions are established technologies and are used
frequently to build concurrent apps, they do have some major drawbacks. Firstly,
they force the developer to split the business logic into small pieces, each
being ran inside of a callback. Secondly, they complicate state management,
because state associated with the business logic cannot be kept *with* the
business logic, it has to be stored elsewhere. Finally, callback-based
concurrency complicates debugging, since a stacktrace at any given point in time
will always originate in the event loop, and will not contain any information on
the chain of events leading to the present moment.

Fibers, in contrast, let the developer express the business logic in a
sequential, easy to read manner: do this, then that. State can be stored right
in the business logic, as local variables. And finally, the sequential
programming style makes it much easier to debug your code, since stack traces
contain the entire history of execution from the app's inception.

## Structured Concurrency

Polyphony's tagline is "fine-grained concurrency for Ruby", because it makes it
really easy to spin up literally thousands of fibers that perform concurrent
work. But running such a large number of concurrent operations also means you
need tools for managing all that concurrency.

For that purpose, Polyphony follows a paradigm called *structured concurrency*.
The basic idea behind structured concurrency is that fibers are organised in a
hierarchy starting from the main fiber. A fiber spun by any given fiber is
considered a child of that fiber, and its lifetime is guaranteed to be limited
to that of its parent fiber. That is why in the example above, the `counter`
fiber is automatically stopped when the main fiber stops running.

The same goes for exception handling. Whenever an error occurs, if no suitable
`rescue` block has been defined for the fiber in which the exception was raised,
the exception will bubble up through the fiber's parent, grandparent etc, until
the exception is handled, up to the main fiber. If the exception was not
handled, the program will exit and dump the exception information just like a
normal Ruby program.

## Controlling Fiber Execution

Polyphony offers a wide range of APIs for controlling fibers that make it easy
to prevent your program turning into an incontrollable concurrent mess. In order
to control fibers, Polyphony introduces various APIs for stopping fibers,
scheduling fibers, awaiting for fibers to terminate, and even restarting them:

```ruby
f = spin do
  puts "going to sleep"
  sleep 1
  puts "done sleeping"
ensure
  puts "stopped"
end

sleep 0.5
f.stop
f.restart
f.await
```

The output of the above program will be:

```
going to sleep
stopped
going to sleep
done sleeping
stopped
```

The `Fiber#await` method waits for a fiber to terminate, and returns the fiber's
return value:

```ruby
a = spin { sleep 1; :foo }
b = spin { a.await }
b.await #=> :foo
```

In the program above the main fiber waits for fiber `b` to terminate, and `b`
waits for fiber `a` to terminate. The return value of `a.await` is `:foo`, and
hence the return value of `b.await` is also `foo`.

If we need to wait for multiple fibers, we can use `Fiber::await` or
`Fiber::select`:

```ruby
# get result of a bunch of fibers
fibers = 3.times.map { |i| spin { i * 10 } }
Fiber.await(*fibers) #=> [0, 10, 20]

# get the fastest reply of a bunch of URLs
fibers = urls.map { |u| spin { [u, HTTParty.get(u)] } }
# Fiber.select returns an array containing the fiber and its result
Fiber.select(*fibers) #=> [fiber, [url, result]]
```

Finally, fibers can be supervised, in a similar manner to Erlang supervision
trees. The `Kernel#supervise` method will wait for all child fibers to terminate
before returning, and can optionally restart any child fiber that has terminated
normally or with an exception:

```ruby
fiber1 = spin { sleep 1; raise 'foo' }
fiber2 = spin { sleep 1 }

supervise # blocks and then propagates the error raised in fiber1
```

## Message Passing

Polyphony also provides a comprehensive solution for using fibers as actors, in
a similar fashion to Erlang processes. Fibers can exchange messages between each
other, allowing each part of a concurrent system to function in a completely
autonomous manner. For example, a chat application can encapsulate each chat
room in a completely self-contained fiber:

```ruby
def chat_room
  subscribers = []

  loop do
    # receive waits for a message to come in
    case receive
    # Using Ruby 2.7's pattern matching
    in [:subscribe, subscriber]
      subscribers << subscriber
    in [:unsubscribe, subscriber]
      subscribers.delete subscriber
    in [:add_message, name, message]
      subscribers.each { |s| s.call(name, message) }
    end
  end
end

CHAT_ROOMS = Hash.new do |h, n|
  h[n] = spin { chat_room }
end
```

Notice how the state (the `subscribers` variable) stays local, and how the logic
of the chat room is expressed in a way that is both compact and easy to extend.
Also notice how the chat room is written as an infinite loop. This is a common
pattern in Polyphony, since fibers can always be stopped at any moment.

The code for handling a chat room user might be expressed as follows:

```ruby
def chat_user_handler(user_name, connection)
  room = nil
  message_subscriber = proc do |name, message|
    connection.puts "#{name}: #{message}"
  end
  while command = connection.gets
    case command
    when /^connect (.+)/
      room&.send [:subscribe, message_subscriber]
      room = CHAT_ROOMS[$1]
    when "disconnect"
      room&.send [:unsubscribe, message_subscriber]
      room = nil
    when /^send (.+)/
      room&.send [:add_message, user_name, $1]
    end
  end
end
```

## Other Concurrency Constructs

Polyphony includes various constructs that complement fibers. Resource pools
provide a generic solution for controlling concurrent access to limited
resources, such as database connections. A resource pool assures only one fiber
has access to a given resource at any time:

```ruby
DB_CONNECTIONS = Polyphony::ResourcePool.new(limit: 5) do
  PG.connect(DB_OPTS)
end

def query_records(sql)
  DB_CONNECTIONS.acquire do |db|
    db.query(sql).to_a
  end
end
```

Throttlers can be useful for rate limiting, for example preventing blacklisting
your system in case it sends too many emails, even across fibers:

```ruby
MAX_EMAIL_RATE = 10 # max. 10 emails per second
EMAIL_THROTTLER = Polyphony::Throttler.new(MAX_EMAIL_RATE)

def send_email(addr, content)
  EMAIL_THROTTLER.process do
    ...
  end
end
```

In addition, various global methods (defined on the `Kernel` module) provide
common functionality, such as using timeouts:

```ruby
# perform an delayed action (in a separate fiber)
after(10) { notify_user }

# perform a recurring action with time drift correction
every(1) { p Time.now }

# perform an operation with timeout without raising an exception
move_on_after(10) { perform_query }

# perform an operation with timeout, raising a Polyphony::Cancel exception
cancel_after(10) { perform_query }
```

## The Polyphony Backend

In order to implement automatic fiber switching when performing blocking
operations, Polyphony introduces a concept called the *system backend*. The system
backend is an object having a uniform interface, that performs all blocking
operations.

While a standard event loop-based solution would implement a blocking call
separately from the fiber scheduling, the system backend integrates the two to
create a blocking call that already knows how to switch and schedule fibers.
For example, in Polyphony all APIs having to do with reading from files or
sockets end up calling `Thread.current.backend.read`, which does all the work.

This design offers some major advantages over other designs. It minimizes memory
allocations of both Ruby objects and C structures. For example, instead of
having to allocate libev watchers on the heap and then pass them around, they
are allocated on the stack instead, which saves both memory and CPU cycles.

In addition, the backend interface includes two methods that allow maximizing
server performance by accepting connections and reading from sockets in a tight
loop. Here's a naive implementation of an HTTP/1 server:

```ruby
require 'http/parser'
require 'polyphony'

def handle_client(socket)
  parser = Http::Parser.new
  reqs = []
  parser.on_message_complete = proc { |env| reqs << { foo: :bar } }

  Thread.current.backend.read_loop(socket) do |data|
    parser << data
    reqs.each { |r| reply(socket, r) }
    reqs.clear
  end
end

def reply(socket)
  data = "Hello world!\n"
  headers = "Content-Type: text/plain\r\nContent-Length: #{data.bytesize}\r\n"
  socket.write "HTTP/1.1 200 OK\r\n#{headers}\r\n#{data}"
end

server = TCPServer.open('0.0.0.0', 1234)
puts "listening on port 1234"

Thread.current.backend.accept_loop(server) do |client|
  spin { handle_client(client) }
end
```

The `#read_loop` and `#accept_loop` backend methods implement tight loops that
provide a significant boost to performance (up to +30% better throughput.)

Currently, Polyphony includes a single system backend based on
[libev](http://pod.tst.eu/http://cvs.schmorp.de/libev/ev.pod). In the future,
Polyphony will include other platform-specific system backends, such as a Windows
backend using
[IOCP](https://docs.microsoft.com/en-us/windows/win32/fileio/i-o-completion-ports),
or an [io_uring](https://unixism.net/loti/what_is_io_uring.html) backend,
which might be a game-changer for writing highly-concurrent Ruby-based web apps.

## Writing Web Apps with Polyphony

Polyphony includes a full-featured web server implementation that supports
HTTP/1, HTTP/2, and WebSockets, can perform SSL termination (with automatic ALPN
protocol selection), and has preliminary support for Rack (the de-facto standard
Ruby web app interface).

The Polyphony HTTP server has a unique design that calls the application's
request handler after all request headers have been received. This allows the
application to better deal with slow client attacks, big file uploads, and also
to minimize costly memory allocation and GC'ing.

Benchmarks will be included here at a later time.

## Integrating Polyphony with other Gems

Polyphony aims to be a comprehensive concurrency solution for Ruby, and to
enable developers to use a maximum of core and stdlib APIs transparently in a
multi-fiber envrionment. Polyphony also provides adapters for common gems such
as postgres and redis, allowing using those gems in a fiber-aware manner.

For gems that do not yet have a fiber-aware adapter, Polyphony offers a general
solution in the form of a thread pool. A thread pool lets you offload blocking
method calls (that block the entire thread) onto worker threads, letting you
continue with other work while waiting for the call to return. For example,
here's how an `sqlite` adapter might work:

```ruby
class SQLite3::Database
  THREAD_POOL = Polyphony::ThreadPool.new

  alias_method :orig_execute, :execute
  def execute(sql, *args)
    THREAD_POOL.process { orig_execute(sql, *args) }
  end
end
```

Other cases might require converting a callback-based interface into a blocking
fiber-aware one. Here's (a simplified version of) how Polyphony uses the
callback-based `http_parser.rb` gem to parse incoming HTTP/1 requests:

```ruby
class HTTP1Adapter
  ...

  def on_headers_complete(headers)
    @pending_requests << Request.new(headers, self)
  end

  def each(&block)
    while (data = @connection.readpartial(8192))
      # feed parser
      @parser << data
      while (request = @pending_requests.shift)
        block.call(request)
        return unless request.keep_alive?
      end
    end
  end

  ...
end
```

In the code snippet above, the solution is quite simple. The fiber handling the
connection loops waiting for data to be read from the socket. Once the data
arrives, it is fed to the HTTP parser. The HTTP parser will call the
`on_headers_complete` callback, which simply adds a request to the requests
queue. The code then continues to handle any requests still in the queue.

## Future Directions

Polyphony is a young project, and will still need a lot of development effort to
reach version 1.0. Here are some of the exciting directions we're working on.

- Support for more core and stdlib APIs
- More adapters for gems with C-extensions, such as `mysql`, `sqlite3` etc
- Use `io_uring` backend as alternative to the libev backend
- More concurrency constructs for building highly concurrent applications
