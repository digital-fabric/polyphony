# Nuclear - async-style concurrency for Ruby

Nuclear is a framework for building concurrent applications in Ruby. Nuclear
provides a simple and lightweight API for asynchronous I/O processing, designed to
maximize both developer happiness and performance. Nuclear provides all the
tools needed for asynchronous programming, making it easier to reason about
your concurrent code.

Under the hood, Nuclear uses [libev](https://github.com/enki/libev) as a
high-performance event reactor that provides timer, I/O and other
primitives that allow async programming. Nuclear uses the libev event reactor
in association with 
[Ruby fibers](https://ruby-doc.org/core-2.5.1/Fiber.html) to achieve
concurrency without having to use multiple threads, locking mechanisms, or
callbacks.

## Features

- Asynchronous programming 
- Asynchronous I/O processing.
- `async`/`await` API for writing asynchronous software in a synchronous style.
- TCP sockets with built-in support for TLS (secure sockets).
- One-shot and recurring timers.
- Various promise-based abstractions such as `generator`, `pulse`, `sleep` etc.
- HTTP client/server implementation:
  - Keep-alive connections
  - Rack interface
  - HTTP 1.0/1.1 [using](https://github.com/tmm1/http_parser.rb) the [node.js HTTP parser](https://github.com/nodejs/http-parser)
  - HTTP 2.0 with [HPACK header compression](https://github.com/igrigorik/http-2)
  - HTTPS with automatic ALPN protocol selection
  - Support for HTTP 2.0 upgrading over plain HTTP
  - HTTP client agent interface
- PostgreSQL client implementation
- Redis client implementation

## Prior Art

- [nio4r](https://github.com/socketry/nio4r/)
- [EventMachine](https://github.com/eventmachine/eventmachine)
- [Trio](https://trio.readthedocs.io/)

## An echo server in nuclear

```ruby
require 'nuclear'

def echo_connection(socket)
  reader = Nuclear::LineReader.new(socket)

  while line = Nuclear.await(reader.gets)
    socket << "You said: #{line}"
  end
end

server = Nuclear::Net::Server.new
server.listen(port: 1234)

Nuclear.async do
  while socket = Nuclear.await(server.connection)
    Nuclear.async { echo_connection(socket) }
  end
end

puts "listening on port 1234"
```

In the example above there are two loops which run concurrently inside separate
fibers. Whenever `await` is called, control is yielded back to the nuclear
reactor. Once a line is received (using `reader.gets`) control is handed back
to the paused fiber, and processing continues. The reactor loop is run
automatically once the program file has been executed (in a similar fashion to
[node.js](https://nodejs.org/))

## Installation

```bash
$ gem install nuclear
```



```ruby
require 'nuclear'

async! do
  loop do
    Nuclear.await Nuclear.sleep(1)
    puts Time.now
  end
end
```

## Nuclear Timers

Nuclear timers allow scheduling of tasks at specific times, optionally with a
specific frequency for recurring timers. In addition, a task can be scheduled
to be run on the next iteration of the reactor loop using `Nuclear.next_tick`.

### Nuclear.timeout(timeout)

Schedules a task to be run after the given timeout:

```ruby
Nuclear.timeout(5) { puts "5 seconds have elapsed" }
```

### Nuclear.interval(interval, offset = nil)

Schedules a task to be run repeatedly at the given frequency. The `offset`
argument can be used to specify the interval for running the given task for the
first time:

```ruby
Nuclear.interval(1) { puts Time.now }
Nuclear.interval(1, 0.5) { puts "in between..." }
```

### Nuclear.next_tick

Schedules a task to be run in the next iteration of the reactor loop:

```ruby
@count = 0

def counter
  @count += 1
  puts @count if @count % 100000 == 0
  Nuclear.next_tick { counter }
end
counter
```

## Promises

A promise represents the future result of an asynchronous operation. A promise
may be fulfilled with either a result value, or an error. Promises can be
chained to create complex asynchronous workflows:

```ruby
# using callbacks, we use recursion
foo { |v| bar(v) { |v| baz(v) } }

# with promises, we can chain operations using then
foo.then { |v| bar(v) }.then { |v| baz(v) }
```

Promises can also be used to catch exceptions:

```ruby
foo.then { bar }.catch { |err| puts "error: #{err}" }
```

