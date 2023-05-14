# @title Tutorial

# Tutorial

In this tutorial we'll show how to build a simple fiber-based server using
Polyphony, how to make it concurrent and how to make it resilient to errors.
We'll assume you have read the [overview](./overview.md). If you haven't yet,
please go and read it now before continuing with this tutorial.

## Building a Simple Echo Server with Polyphony

Here's what we want to build: a concurrent echo server. Our server will accept
TCP connections and send back whatever it receives from the client.

We'll start by opening a server socket:

```ruby
require 'polyphony'

server = TCPServer.open('127.0.0.1', 1234)
puts 'Echoing on port 1234...'
```

Next, we'll add a loop accepting connections:

```ruby
while (client = server.accept)
  handle_client(client)
end
```

The `handle_client` method is almost trivial:

```ruby
def handle_client(client)
  while (data = client.gets)
    client << data
  end
rescue Errno::ECONNRESET
  puts 'Connection reset by client'
end
```

## Adding Concurrency

Up until now, we did nothing about concurrency. In fact, our code will not be
able to handle more than one client at a time, because the accept loop cannot
continue to run until the call to `#handle_client` returns, and that will not
happen as long as the read loop is not done.

Fortunately, Polyphony makes it super easy to do more than one thing at once.
Let's spin up a separate fiber for each client:

```ruby
while (client = server.accept)
  spin { handle_client(client) }
end
```

Now, our little program can effectively handle thousands of clients, all with a
little sprinkling of `spin`. The call to `server.accept` suspends the main fiber
until a connection is made, allowing other fibers to run while it's waiting.
Likewise, the call to `client.gets` suspends the *client's fiber* until incoming
data becomes available. Again, all of that is handled automatically by
Polyphony, and the only hint that our program is concurrent is that little
innocent call to `#spin`.

Here's a flow chart showing the transfer of control between the different fibers:

<img src="https://github.com/digital-fabric/polyphony/raw/master/docs/assets/echo-fibers.png">

Let's consider the advantage of the Polyphony concurrency model:

- We didn't need to create custom handler classes with callbacks.
- We didn't need to use custom classes or APIs for our networking code.
- Each task is expressed sequentially. Our code is terse, easy to read and, most
  importantly, expresses the order of events clearly and without having our
  logic split across different methods.
- We have a server that can scale to thousands of clients without breaking a
  sweat.

## Handling Inactive Connections

Now that we have a working concurrent echo server, let's add some bells and
whistles. First of all, let's get rid of clients that are not active. We'll do
this by wrapping our read loop in a call to `cancel_after`:

```ruby
def handle_client(client)
  cancel_after(10) do |timeout|
    while (data = client.gets)
      timeout.restart
      client << data
    end
  end
rescue Polyphony::Cancel
  client.puts 'Closing connection due to inactivity.'
rescue Errno::ECONNRESET
  puts 'Connection reset by client'
ensure
  client.close
end
```

The call to `#cancel_after` spins up a new fiber that will sleep for 10 seconds,
then cancel its parent. The call to `client.gets` blocks until new data is
available. If no new data is available, the `timeout` fiber will finish
sleeping, and then cancel the client handling fiber by raising a
`Polyphony::Cancel` exception. However, if new data is received, the `timeout`
fiber is restarted, causing it to begin sleeping again for 10 seconds. If the
client has closed the connection, or some other exception occurs, the `timeout`
fiber is automatically stopped as it is a child of the fiber running the
`handle_client` method.

The habit of always cleaning up using `ensure` in the face of potential
interruptions is a fundamental element of using Polyphony correctly. This makes
your code robust, even in a highly chaotic concurrent execution environment
where fibers can be started, restarted and interrupted at any time.

## Implementing graceful shutdown

Let's now add graceful shutdown to our server. This means that when the server
is stopped we'll first stop accepting new connections, but we'll let any already
connected clients keep their sessions.

Polyphony's concurrency model is structured. Fibers are limited to the lifetime
of their direct parent. When the main fiber terminates (on program exit), it
will terminate all its child fibers, each of which will in turn terminate its
own children. The termination of child fibers is implemented by sending each
child fiber a `Polyphony::Terminate` exception. We can implement custom
termination logic simply by adding an exception handler for
`Polyphony::Terminate`:

```ruby
# We first refactor the echo loop into a method
def client_loop(client, timeout = nil)
  while (data = client.gets)
    timeout&.reset
    client << data
  end
end

def handle_client(client)
  cancel_after(10) { |timeout| client_loop(client, timeout) }
rescue Polyphony::Cancel
  client.puts 'Closing connection due to inactivity.'
rescue Polyphony::Terminate
  # We add a handler for the Terminate exception, and give
  client.puts 'Server is shutting down. You have 5 more seconds...'
  move_on_after(5) do
    client_loop(client)
  end
rescue Errno::ECONNRESET
  puts 'Connection reset by client'
ensure
  timeout.stop
  client.close
end
```

## Conclusion

In this tutorial, we have shown how Polyphony can be used to create robust,
highly concurrent Ruby applications. As we have discussed above, Polyphony
provides a comprehensive set of tools that make it simple and intuitive to write
concurrent applications, with features such as structured concurrency (for
controlling fiber lifetime), timeouts (for handling inactive or slow clients),
custom termination logic (for implementing graceful shutdown).

Here's the complete source code for our Polyphony-based echo server:

```ruby
require 'polyphony/auto_run'

server = TCPServer.open('127.0.0.1', 1234)
puts 'Echoing on port 1234...'

def client_loop(client, timeout = nil)
  while (data = client.gets)
    timeout&.reset
    client << data
  end
end

def handle_client(client)
  cancel_after(10) { |timeout| client_loop(client, timeout) }
rescue Polyphony::Cancel
  client.puts 'Closing connection due to inactivity.'
rescue Polyphony::Terminate
  client.puts 'Server is shutting down. You have 5 more seconds...'
  move_on_after(5) do
    client_loop(client)
  end
rescue Errno::ECONNRESET
  puts 'Connection reset by client'
ensure
  timeout.stop
  client.close
end

while (client = server.accept)
  spin { handle_client(client) }
end
```
