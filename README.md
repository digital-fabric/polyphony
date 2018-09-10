# Nuclear - a lightweight asynchronous framework for Ruby

Nuclear is a reactor framework for Ruby. Nuclear provides a lightweight API for
asynchronous I/O processing, designed to maximize both developer happiness and
performance. Nuclear provides all the tools needed to write asynchronous
applications in a synchronous style, making the code much easier to understand
and reason about.

Under the hood, nuclear uses [nio4r](https://github.com/socketry/nio4r/) and
[Ruby fibers](https://ruby-doc.org/core-2.5.1/Fiber.html) to provide
concurrency without having to use multiple threads and locking mechanisms.

Nuclear provides the following features:

- Asynchronous I/O processing.
- `async`/`await` API for writing asynchronous software in a synchronous style.
- TCP sockets with built-in support for TLS (secure sockets).
- One-shot and recurring timers.
- Various promise-based abstractions such as `generator`, `pulse`, `sleep` etc.

Current plugins include:

- HTTP client/server, with support for HTTPS and HTTP/2
- PostgreSQL client
- Redis client

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

## Getting Started

Nuclear is a framework that provides all the tools needed to write concurrent
programs in Ruby. Nuclear allows the developer to write in a synchronous style,
without using blocking calls, threads or any locking mechanisms.

At its core, Nuclear runs a reactor loop that checks for any elapsed timers, or
any I/O descriptors (such as sockets or files) that have become readable or 
writable. Once such an event has been detected, control is passed to code that
handles the event. Such code is normally contained in a callback `Proc`, or an
`await` expression that involves a `Promise`.

Here is an example using callbacks:

```ruby
require 'nuclear'

Nuclear.interval(1) { puts Time.now }
```

And here's an example using `async`/`await`:

```ruby
require 'nuclear'

Nuclear.async do
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

To be continued...