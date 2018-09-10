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

## Developer's guide