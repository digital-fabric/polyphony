---
layout: page
title: A Gentle Introduction to Polyphony
nav_order: 2
parent: Getting Started
permalink: /getting-started/tutorial/
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




Let's examine the fiber switching dance by looking at a concrete example:

```ruby
require 'polyphony'

(1..3).each do |i|
  spin do
    puts "Sleeping for #{i} seconds"
    sleep i
    puts "Done sleeping for #{i} seconds"
  end
end
suspend
puts "We're done!"
```

We start 3 separate fibers using the `#spin` primitive, each fiber sleeping for
a certain period of time before terminating. Those three fibers are marked as
*runnable* and put on a run queue, but will not start executing until the main
fiber has been put in a suspended state. Finally, the main fiber calls
`#suspend`, allowing the other fibers to start running.

<p class="img-figure"><img src="../../assets/img/sleep-fibers.svg"></p>

One by one, the three fibers call `#sleep`. Each call to `#sleep` causes the
current fiber to suspend, and a timer to be created, and control is passed to
the next runnable fiber. When no more runnable fibers remain, Polyphony finally
runs the event loop and waits for at least one event to occur. After 1 second,
the first timer fires, and the corresponding fiber is put back on the run queue
and marked as *runnable*. Once the event loop has finished running, the first
runnable fiber is given control. Once all 3 fibers have terminated, the main
fiber is resumed and the program terminates.

The output for the program will be:

```
Sleeping for 1 seconds
Sleeping for 2 seconds
Sleeping for 3 seconds
Done sleeping for 1 seconds
Done sleeping for 2 seconds
Done sleeping for 3 seconds
We're done
```

What happens behind the scenes 

# 

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