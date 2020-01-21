---
layout: page
title: Tutorial
nav_order: 2
parent: Getting Started
permalink: /getting-started/tutorial/
---
# Tutorial

## Building a Simple Echo Server with Polyphony

In order to demonstrate how to use Polyphony, let's write an echo server, which
accepts TCP connections and sends back whatever it receives from the client.

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
    client.write('you said: ', data.chomp, "!\n")
  end
rescue Errno::ECONNRESET
  puts 'Connection reset by client'
end
```

### Adding Concurrency

Up until now, we did nothing about concurrency. In fact, our code will not be
able to handle more than one client at a time, because the accept loop cannot
continue to run until the call to `#handle_client` returns, and that will not
happen as long as the read loop is not done.

Fortunately, Polyphony makes it super easy to do more than one thing at once.
Let's spin up a separate coprocess for each client:

```ruby
while (client = server.accept)
  spin { handle_client(client) }
end
```

Now, our little program can handle virtually thousands of clients, all with a
little sprinkling of `spin`. Let's discuss how this works. The `Kernel#spin`
method starts a new coprocess, a separate context of execution based on [Ruby
fibers](https://ruby-doc.org/core-2.6.5/Fiber.html). A coprocess may be
arbitrarily suspended and resumed, and Polyphony takes advantage of this fact
to implement a concurrent execution environment without the use of threads.

The call to `server.accept` suspends the *root coprocess* until a connection is
made, allowing other coprocesses to continue running. Likewise, the call to
`client.gets` suspends the *client's coprocess* until incoming data becomes
available. All this is handled automatically by Polyphony, and the only hint
that our program is concurrent is that innocent call to `spin`.

Let's consider the advantage of the Polyphony approach:

- We didn't need to create custom handler classes with callbacks.
- We didn't need to use custom classes or APIs for our networking code.
- Our code is terse, easy to read and - most importantly - expresses the order
  of events clearly and without being split across callbacks.
- We have a server that can scale to thousands of clients without breaking a
  sweat.

## Handling Inactive Connections

Now that we have a working concurrent echo server, let's add some bells and
whistles. First of all, let's get rid of clients that are not active. We'll do
this by using a Polyphony construct called a cancel scope. Cancel Scope define
an execution context that can cancel any operation ocurring within its scope:

```ruby
def handle_client(client)
  Polyphony::CancelScope.new(timeout: 10) do |scope|
    while (data = client.gets)
      scope.reset_timeout
      client.write('you said: ', data.chomp, "!\n")
    end
  end
rescue Errno::ECONNRESET
  puts 'Connection reset by client'
ensure
  client.close
end
```

The cancel scope is initialized with a timeout of 10 seconds. Any blocking
operation ocurring within the cancel scope will be interrupted once 10 seconds
have elapsed. In order to keep the connection alive while the client is active,
we call `scope.reset_timeout` each time data is received from the client, and
thus reset the cancel scope timer.

In addition, we use an `ensure` block to make sure the client connection is
closed, whether or not it was interrupted by the cancel scope timer. The habit
of always cleaning up using `ensure` in the face of interruptions is a
fundamental element of using Polyphony. It makes your code robust, even in a
highly concurrent execution environment.

Here's the complete source code for our Polyphony-based echo server:

```ruby
require 'polyphony/auto_run'

server = TCPServer.open('127.0.0.1', 1234)
puts 'Echoing on port 1234...'

def handle_client(client)
  Polyphony::CancelScope.new(timeout: 10) do |scope|
    while (data = client.gets)
      scope.reset_timeout
      client.write('you said: ', data.chomp, "!\n")
    end
  end
rescue Errno::ECONNRESET
  puts 'Connection reset by client'
ensure
  client.close
end

while (client = server.accept)
  spin { handle_client(client) }
end
```

## Learning More

Polyphony is still new, and the present documentation is far from being
complete. For more information read the [technical overview](technical-overview/concurrency.md)
or look at the [included examples](#).