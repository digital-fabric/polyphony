---
layout: page
title: Frequently Asked Questions
nav_order: 100
---
# Frequently Asked Questions

### Why not just use callbacks instead of fibers?

It is true that reactor engines such as libev use callbacks to handle events.
There's also programming platforms such as [node.js](https://nodejs.org/) that
base their entire API on the callback pattern.
[EventMachine](https://www.rubydoc.info/gems/eventmachine/1.2.7) is a popular
reactor library for Ruby that uses callbacks for handling events.

Using callbacks means splitting your application logic into disjunct pieces of
code. Consider the following implementation of an echo server using
EventMachine:

```ruby
require 'eventmachine'

module EchoServer
  def post_init
    puts '-- someone connected to the echo server!'
  end

  def receive_data data
    send_data ">>>you sent: #{data}"
    close_connection if data =~ /quit/i
  end

  def unbind
    puts '-- someone disconnected from the echo server!'
  end
end

# Note that this will block the current thread.
EventMachine.run {
  EventMachine.start_server '127.0.0.1', 8081, EchoServer
}
```

The client-handling code is split across three different callback methods.
Compare this to the following equivalent using Polyphony:

```ruby
require 'polyphony'

server = TCPServer.open('127.0.0.1', 8081)
while (client = server.accept)
  spin do
    puts '-- someone connected to the echo server!'
    while (data = client.gets)
      client << ">>>you sent: #{data}"
      break if data =~ /quit/i
    end
  ensure
    client.close
    puts '-- someone disconnected from the echo server!'
  end
end
```

The Polyphony version is both more terse and explicit at the same time. It
explicitly accepts connections on the server port, and the entire logic handling
each client connection is contained in a single block. The order of the
different actions - printing to the console, then echoing client messages, then
finally closing the client connection and printing again to the console - is
easy to grok. The echoing of client messages is also explicit: a simple loop
waiting for a message, then responding to the client. In addition, we can use an
`ensure` block to correctly cleanup even if exceptions are raised while handling
the client.

Using callbacks also makes it much more difficult to debug your program. when
callbacks are used to handle events, the stack trace will necessarily start at
the reactor, and thus lack any information about how the event came to be in the
first place. Contrast this with Polyphony, where stack traces show the entire
_sequence of events_ leading up to the present point in the code.

In conclusion:

* Callbacks cause the splitting of logic into disjunct chunks.
* Callbacks do not provide a good error handling solution.
* Callbacks often lead to code bloat.
* Callbacks are harder to debug.

### If callbacks suck, why not use promises?

Promises have gained a lot of traction during the last few years as an  
alternative to callbacks, above all in the Javascript community. While promises
have been at a certain point considered for use in Polyphony, they were not
found to offer enough of a benefit. Promises still cause split logic, are quite
verbose and provide a non-native exception handling mechanism. In addition, they
do not make it easier to debug your code.

### Why is awaiting implicit? Why not use explicit async/await?

Actually, async/await was contemplated while developing Polyphony, but at a
certain point it was decided to abandon these methods / decorators in favor of a
more implicit approach. The most crucial issue with async/await is that it
prevents the use of anything from Ruby's stdlib. Any operation involving stdlib
classes needs to be wrapped in boilerplate.

Instead, we have decided to make blocking operations implicit and thus allow the
use of common APIs such as `Kernel#sleep` or `IO.popen` in a transparent manner.
After all, these APIs in their stock form block execution just as well.

### Why use `Fiber#transfer` and not `Fiber#resume`?

The API for `Fiber.yield`/`Fiber#resume` is stateful and is intended for the
asymmetric execution of coroutines. This is useful when using generators, or
other cases where one coroutine acts as a "server" and another as a "client". In
Polyphony's case, all fibers are equal, and control can be transferred freely
between them, which is much easier to achieve using `Fiber#transfer`. In
addition, using `Fiber#transfer` allows us to perform blocking operations from
the main fiber, which is not possible when using `Fiber#resume`.

### Why is Polyphony not split into multiple gems?

Polyphony is currently at an experimental stage, and its different APIs are
still in flux. For that reason, all the different parts of Polyphony are
currently kept in a single gem. Once things stabilize, and as Polyphony
approaches version 1.0, it will be split into separate gems, each with its own
functionality.

### Can I use Polyphony in a multithreaded program?

Yes, as of version 0.27 Polyphony implements per-thread fiber-scheduling. It is
however important to note that Polyphony places the emphasis on a multi-fiber
concurrency model, which is highly beneficial for I/O-bound workloads, such as
web servers and web apps.

Because of Ruby's [global interpreter lock](https://en.wikipedia.org/wiki/Global_interpreter_lock),
multiple threads can not in fact run in parallel, and this is actually one of
the reasons fibers are such a better fit for I/O bound Ruby programs. Threads
should really be used when performing synchronous operations that are not
fiber-aware, such as running an expensive SQLite query, or some other expensive
system call.

### How Does Polyphony Fit Into the Ruby's Future Concurrency Plans

To our understanding, two things are currently on the horizon when it comes to
concurrency in Ruby: [auto-fibers](https://bugs.ruby-lang.org/issues/13618), and
[guilds](https://olivierlacan.com/posts/concurrency-in-ruby-3-with-guilds/).
While the auto-fibers proposal introduces an event reactor into Ruby and
automates waiting for file descriptors to become ready, allowing scheduling
other fibers meanwhile. It is still too early to see how Polyphony can coexist
with that. Another proposal is the addition of a fiber-aware [event
selector](https://bugs.ruby-lang.org/issues/14736). It is our intention to
eventually contribute to the discussion in this area by proposing a uniform
fiber scheduler interface that could be implemented in pure Ruby in order to
support all platforms and multiple Ruby runtimes.

The guilds proposal, on the other hand, promises to be a perfect match for
Polyphony's fiber-based concurrency model. Guilds will allow true parallelism
and together with Polyphony will allow taking full advantage of multiple CPU
cores in a single Ruby process.

### Can I run Rails using Polyphony?

We haven't yet tested Rails with Polyphony, but most probably not. We do plan to
support running Rails in an eventual release.

### How can I contribute to Polyphony?

The Polyphony repository is at https://github.com/digital-fabric/polyphony. Feel
free to create issues and contribute pull requests.

### Who is behind this project?

I'm Sharon Rosner, an independent software developer living in France. Here's my
[github profile](https://github.com/ciconia). You can contact me by writing to
[noteflakes@gmail.com](mailto:ciconia@gmail.com).