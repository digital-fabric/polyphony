---
layout: page
title: Tutorial
parent: Getting Started
nav_order: 2
---

# Tutorial
{: .no_toc }

## Table of contents
{: .no_toc .text-delta }

- TOC
{:toc}

---

Polyphony is a new Ruby library aimed at making writing concurrent Ruby apps
easy and fun. In this article, we'll introduce Polyphony's fiber-based
concurrency model, some of Polyphony's API, and demonstrate how to solve some
simple situations related to concurrent computing.

## What are Fibers and What are They Good For?

Fibers are some of Ruby's most underappreciated hidden gems. Up until now,
fibers have been used mostly as the underlying mechanism for implementing
lazy enumerators and asynchronous generators. Fibers encapsulate, in short,
an execution context that can be paused and resumed at will.

Fibers are also at the heart of Polyphony's concurrency model. Polyphony employs
fibers as a way to run multiple tasks at once, each task advancing at its own
pace, pausing when waiting for an event to occur, and automatically resuming
when that event has occurred.

Take for example a web app: in order to fulfil an incoming request, multiple
steps are required: querying the database, fetching cached entries from Redis,
talking to third-party services such as Twilio or AWS S3. Each step can last
tens of milliseconds, and blocks the current thread. Such an app is said to be
I/O-bound, that is, it mostly spends its time waiting for some external
services.

The traditional approach to handling multiple requests concurrently is to employ
multiple threads or processes, but this approach has numerous disavantages:

- Both threads and processes are heavyweight, in both memory consmption and
  the cost associated with context-switching.
- Threads introduce hard-to-debug race conditions, and do not offer true
  parallelism, owing to Ruby's GVL.
- Processes are more difficult to coordinate, since they do not share memory.
- Both threads and processes are limited to a few thousand at best on a single
  machine. Trying to spawn a thread per client essentially limits the scaling
  capacity of your system.
  
Polyphony eschews both threads and processes in favor of fibers as the basic
unit of concurrency. The idea is that any time a blocking I/O operation occurs,
the current fiber is paused, and another fiber which has been marked as
*runnable* is resumed. This way, your Ruby code can keep on handling incoming
HTTP requests as they come with a scaling capacity that is virtually only
limited by available memory.

## Switchpoints and the Fiber-Switching Dance

In order to make pausing and resuming fibers completely automatic and painfree,
we need to know when an operation is going to block, and when it can be
completed without blocking. Operations that might block execution are considered
*switchpoints*. A switchpoint is a point in time at which control might switch
from the currently running fiber to another fiber that is in a runnable state.
Switchpoints may occur in any of the following cases:

- On a call to any blocking operation, such as `#sleep`, `Fiber#await`,
  `Thread#join` etc.
- On fiber termination
- On a call to `#suspend`
- On a call to `#snooze`
- On a call to `Thread#switch_fiber`

At any switchpoint, the following takes place:

- Check if any fiber is runnable, that is, ready to continue processing.
- If no fiber is runnable, watch for events (see below) and wait for at least
  one fiber to become runnable.
- Pause the current fiber and switch to the first runnable fiber, which resumes
  at the point it was last paused.

The automatic switching between fibers is complemented by employing
[libev](http://software.schmorp.de/pkg/libev.html), a multi-platform high
performance event reactor that allows listening to I/O, timer and other events.
At every switchpoint where no fibers are runnable, the libev evet loop is run
until events occur, which in turn cause the relevant fibers to become runnable.

Let's examine a simple example:

```ruby
require 'polyphony'

spin do
  puts "Going to sleep..."
  sleep 1
  puts "Woke up"
end

suspend
puts "We're done"
```

The above program does nothing exceptional, it just sleeps for 1 second and
prints a bunch of messages. But it is enough to demonstrate how concurrency
works in Polyphony. Here's a flow chart of the transfer of control:

<p class="img-figure"><img src="../../assets/img/sleeping-fiber.svg"></p>

Here's the actual sequence of execution (in pseudo-code)

```ruby
# (main fiber)
sleeper = spin { ... } # The main fiber spins up a new fiber marked as runnable
suspend # The main fiber suspends, waiting for all other work to finish
  Thread.current.switch_fiber # Polyphony looks for other runnable fibers
  
  # (sleeper fiber)
  puts "Going to sleep..." # The sleeper fiber starts running
  sleep 1 # The sleeper fiber goes to sleep
    Gyro::Timer.new(1, 0).await # A timer event watcher is setup and yields
      Thread.current.switch_fiber # Polyphony looks for other runnable fibers
        Thread.current.agent.poll # With no work left, the event loop is ran
          fiber.schedule # The timer event fires, scheduling the sleeper fiber
  # <= The sleep method returns
  puts "Woke up"
  Thread.current.switch_fiber # With the fiber done, Polyphony looks for work

# with no more work, control is returned to the main fiber
# (main fiber)
# <=
# With no more work left, the main fiber is resumed and the suspend call returns
puts "We're done"
```

What we have done in fact is we multiplexed two different contexts of execution
(fibers) onto a single thread, each fiber continuing at its own pace and
yielding control when waiting for something to happen. This context-switching
dance, performed automatically by Polyphony behind the scenes, enables building
highly-concurrent Ruby apps, with minimal impact on performance.

## Building a Simple Echo Server with Polyphony

Let's now turn our attention to something a bit more useful: a concurrent echo
server. Our server will accept TCP connections and send back whatever it receives
from the client.

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

<p class="img-figure"><img src="../../assets/img/echo-fibers.svg"></p>

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
this by setting up a timeout fiber that cancels the fiber dealing with the connection

```ruby
def handle_client(client)
  timeout = cancel_after(10)
  while (data = client.gets)
    timeout.restart
    client << data
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
fiber is restarted, causing to begin sleeping again for 10 seconds. If the
client has closed the connection, or some other exception occurs, the `timeout`
fiber is automatically stopped as it is a child of the client handling fiber.

The habit of always cleaning up using `ensure` in the face of potential
interruptions is a fundamental element of using Polyphony correctly. This makes
your code robust, even in a highly chaotic concurrent execution environment
where tasks can be started, restarted and interrupted at any time.

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
  timeout = cancel_after(10)
  client_loop(client, timeout)
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
  timeout = cancel_after(10)
  client_loop(client, timeout)
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

## What Else Can I Do with Polyphony?

Polyphony currently provides support for any library that uses Ruby's stock
`socket` and `openssl` classes. Polyphony also includes adapters for the `pg`,
`redis` and `irb` gems. It also includes an implementation of an integrated HTTP
1 / HTTP 2 / websockets web server with support for TLS termination, ALPN
protocol selection and preliminary rack support.

## Fibers are the Future!

Implementing concurrency at the level of fibers opens up so many new
possibilities for Ruby. Polyphony has the performance characteristics and
provides the necessary tools for transforming how concurrent Ruby apps are
written. Polyphony is still new, and the present documentation is far from being
complete. To learn more about Polyphony, read the [technical
overview](../../main-concepts/design-principles/). For more examples please
consult the [Github
repository](https://github.com/digital-fabric/polyphony/tree/master/examples).