# Introduction

Nuclear is a framework for building concurrent applications in Ruby. Nuclear provides a simple and lightweight API for asynchronous I/O processing, designed to maximize both developer happiness and performance.

Nuclear harnesses the power of [Ruby fibers](https://ruby-doc.org/core-2.5.1/Fiber.html) to provide a cooperative, sequential coroutine-based concurrency model that is much easier to write, read, and reason about. Under the hood, Nuclear uses [libev](https://github.com/enki/libev) as a high-performance event reactor that provides timer and I/O watchers and other synchronization primitives.

## An echo server in Nuclear

```ruby
require 'nuclear'

spawn do
  server = Nuclear::Net.tcp_serve(1234)
  while client = await server.accept do
    spawn do
      while data = await client.read
        await client.write(data)
      end
    end
  end
end
```

## Features

* `async`/`await` API for writing asynchronous software in a synchronous style.
* non-blocking I/O and networking operations
* One-shot and recurring timers.
* Supervisor API for supervising short-lived and long-running tasks
* TCP sockets with built-in support for TLS \(secure sockets\).
* HTTP client/server implementation:
  * Keep-alive connections
  * Rack interface
  * HTTP 1.0/1.1 [using](https://github.com/tmm1/http_parser.rb) the [node.js HTTP parser](https://github.com/nodejs/http-parser)
  * HTTP 2.0 with [HPACK header compression](https://github.com/igrigorik/http-2)
  * HTTPS with automatic ALPN protocol selection
  * Support for HTTP 2.0 upgrading over plain HTTP
  * HTTP client agent interface
* PostgreSQL client implementation
* Redis client implementation

## Prior Art

* [nio4r](https://github.com/socketry/nio4r/)
* [EventMachine](https://github.com/eventmachine/eventmachine)
* [Trio](https://trio.readthedocs.io/)

## Installation

```bash
$ gem install nuclear
```

```ruby
require 'nuclear'

spawn do
  puts 
  await sleep(1)
  puts Time.now
  loop do
  end
end
```

## Nuclear Timers

Nuclear timers allow scheduling of tasks at specific times, optionally with a specific frequency for recurring timers. In addition, a task can be scheduled to be run on the next iteration of the reactor loop using `Nuclear.next_tick`.

### Nuclear.timeout\(timeout\)

Schedules a task to be run after the given timeout:

```ruby
Nuclear.timeout(5) { puts "5 seconds have elapsed" }
```

### Nuclear.interval\(interval, offset = nil\)

Schedules a task to be run repeatedly at the given frequency. The `offset` argument can be used to specify the interval for running the given task for the first time:

```ruby
Nuclear.interval(1) { puts Time.now }
Nuclear.interval(1, 0.5) { puts "in between..." }
```

### Nuclear.next\_tick

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

A promise represents the future result of an asynchronous operation. A promise may be fulfilled with either a result value, or an error. Promises can be chained to create complex asynchronous workflows:

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

