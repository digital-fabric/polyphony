---
layout: page
title: A Gentle Introduction to Polyphony
nav_order: 2
parent: Getting Started
permalink: /getting-started/tutorial/
prev_title: Installing Polyphony
next_title: Design Principles
---
# A Gentle Introduction to Polyphony

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
        Thread.current.selector.run # With no work left, the event loop is ran
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
this by using a Polyphony construct called a cancel scope. Cancel scopes define
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
of always cleaning up using `ensure` in the face of potential interruptions is a
fundamental element of using Polyphony correctly. It makes your code robust,
even in a highly chaotic concurrent execution environment where tasks can be
interrupted at any time.

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

## Waiting and Interrupting

Polyphony makes it very easy to run multiple concurrent fibers. You can
basically start a fiber for any operation that involves talking to the outside
world - running a database query, making an HTTP request, sending off a webhook
invocation etc. While it's trivial to spin off thousands of fibers, we'd also
like a way to control all those fibers.

Polyphony provides a number of tools for controlling fiber execution. Let's
examine some of these tools and how they work. Suppose we have a fiber that was
previously spun:

```ruby
fiber = spin { do_some_work }
```

We can wait for the fiber to terminate:

```ruby
fiber.await # alternatively fiber.join
```

Notice that the await call returns the return value of the fiber block:

```ruby
fiber = spin { 2 + 2}
fiber.await #=> 4
```

We can also stop the fiber at any point:

```ruby
fiber.stop # or fiber.interrupt
```

We can inject a return value for the fiber using `stop`:

```ruby
fiber = spin do
  sleep 1
  1 + 1
end

spin { puts "1 + 1 = #{fiber.await} wha?" }

fiber.stop(3)
suspend
```

We can also *cancel* the fiber, which raises a `Polyphony::Cancel` exception:

```ruby
fiber.cancel!
```

And finally, we can interrupt the fiber with an exception raised in its current
context:

```ruby
fiber.raise 'foo'
```

For more information on how exceptions are handled in Polyphony, see [exception
handling](../../technical-overview/exception-handling/).

## Supervising - controlling multiple fibers at once

Here's a simple example that we'll use to demonstrate some of the tools provided
by Polyphony for controlling fibers. Let's build a script that fetches the local
time for multiple time zones:

```ruby
require 'polyphony'
require 'httparty'
require 'json'

def get_time(tzone)
  res = HTTParty.get("http://worldtimeapi.org/api/timezone/#{tzone}")
  json = JSON.parse(res.body)
  Time.parse(json['datetime'])
end

zones = %w{
  Europe/London Europe/Paris Europe/Bucharest America/New_York Asia/Bangkok
}
zones.each do |tzone|
  spin do
    time = get_time(tzone)
    puts "Time in #{tzone}: #{time}"
  end
end

suspend
```

Now that we're familiar with the use of the `#spin` method, we know that all
those HTTP requests will be processed concurrently, and we can expect those 5
separate requests to occur within a fraction of a second (depending on our
machine's location). Also notice how we just used `httparty` with fiber-level
concurrency, without any boilerplate or employing special wrapper classes.

Just as before, we suspend the main fiber after spinning off the worker fibers,
in order to wait for everything else to be done. But what if we needed to do
other work? For example, we might want to collect the different local times into
a hash to be processed later. In that case, we can use a `Supervisor`:

```ruby
def get_times(zones)
  Polyphony::Supervisor.new do |s|
    zones.each do |tzone|
      s.spin { [tzone, get_time(tzone)] }
    end
  end
end

get_times(zones).await.each do |tzone, time|
  puts "Time in #{tzone}: #{time}"
end
```

There's quite a bit going on here, so let's break it down. We first construct a
supervisor and spin our fibers in its context using `Supervisor#spin`.

```ruby
Polyphony::Supervisor.new do |s|
  ...
  s.spin { ... }
  ...
end
```

Once our worker fibers are spun, the supervisor can be used to control them. We
can wait for all fibers to terminate using `Supervisor#await`, which returns an
array with the return values of all fibers (in the above example, each fiber
returns the time zone and the local time).

```ruby
results = supervisor.await
```

We can also select the result of the first fiber that has finished executing.
All the other fibers will be interrupted:

```ruby
result, fiber = supervisor.select
```

(Notice how `Supervisor#select` returns both the fiber's return value and the
fiber itself).

We can also interrupt all the supervised fibers by using `Supervisor#interrupt`
(or `#stop`) just like with single fibers:

```ruby
supervisor.interrupt
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
overview](../../technical-overview/design-principles/). For more examples please
consult the [Github
repository](https://github.com/digital-fabric/polyphony/tree/master/examples).