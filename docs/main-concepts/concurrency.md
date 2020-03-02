---
layout: page
title: Concurrency the Easy Way
nav_order: 1
parent: Main Concepts
permalink: /main-concepts/concurrency/
prev_title: Tutorial
next_title: How Fibers are Scheduled
---
# Concurrency the Easy Way

Concurrency is a major consideration for modern programmers. Applications and
digital platforms are nowadays expected to do multiple things at once: serve
multiple clients, process multiple background jobs, talk to multiple external
services. Concurrency is the property of our programming environment allowing us
to schedule and control multiple ongoing operations.

Traditionally, concurrency has been achieved by using multiple processes or
threads. Both approaches have proven problematic. Processes consume relatively a
lot of memory, and are relatively difficult to coordinate. Threads consume less
memory than processes and make it difficult to synchronize access to shared
resources, often leading to race conditions and memory corruption. Using threads
often necessitates either using special-purpose thread-safe data structures, or
otherwise protecting shared resource access using mutexes and critical sections.
In addition, dynamic languages such as Ruby and Python will synchronize multiple
threads using a global interpreter lock, which means thread execution cannot be
parallelized. Furthermore, the amount of threads and processes on a single
system is relatively limited, to the order of several hundreds or a few thousand
at most.

Polyphony offers a third way to write concurrent programs, by using a Ruby
construct called [fibers](https://ruby-doc.org/core-2.6.5/Fiber.html). Fibers,
based on the idea of [coroutines](https://en.wikipedia.org/wiki/Coroutine),
provide a way to run a computation that can be suspended and resumed at any
moment. For example, a computation waiting for a reply from a database can
suspend itself, transferring control to another ongoing computation, and be
resumed once the database has sent back its reply. Meanwhile, another
computation is started that opens a socket to a remote service, and then
suspends itself, waiting for the connection to be established.

This form of concurrency, called cooperative concurrency (in contrast to
pre-emptive concurrency, like in threads and processes), offers many advantages,
especially for applications that are [I/O
bound](https://en.wikipedia.org/wiki/I/O_bound). Fibers are very lightweight
(starting at about 10KB), can be context-switched faster than threads or
processes, and literally millions of them can be created on a single system -
the only limiting factor is available memory.

Polyphony takes Ruby's fibers and adds a way to schedule and switch between them
automatically whenever a blocking operation is started, such as waiting for a
TCP connection to be established, for incoming data on an HTTP conection, or for
a timer to elapse. In addition, Polyphony patches the stock Ruby classes to
support its concurrency model, letting developers use all of Ruby's stdlib, for
example `Net::HTTP` and `Mail` while reaping the benefits of lightweight,
fine-grained, performant, fiber-based concurrency.

Writing concurrent applications using Polyphony's fiber-based concurrency model
offers a significant performance advantage. Complex concurrent tasks can be
broken down into many fine-grained concurrent operations with very low overhead.
More importantly, this concurrency model lets developers express their ideas in
a sequential fashion, leading to source code that is much easier to read and
understand, compared to callback-style programming.

## Fibers - Polyphony's basic unit of concurrency

Polyphony extends the core `Fiber` class with additional functionality that
allows scheduling, synchronizing, interrupting and otherwise controlling running
fibers. Starting a concurrent operation inside a fiber is as simple as a `spin`
method call:

```ruby
while (connection = server.accept)
  spin { handle_connection(connection) }
end
```

In order to facilitate developing applications that employ complex concurrent
patterns and can scale easily, Polyphony employs a [structured
approach](https://en.wikipedia.org/wiki/Structured_concurrency) to controlling
fiber lifetime. A spun fiber is considered the *child* of the fiber from which
it was spun, and is always limited to the life time of its parent:

```ruby
parent = spin do
  do_something
  child = spin do
    do_some_other_stuff
  end
  # the child fiber is guaranteed to stop executing before the parent fiber
  # terminates
end
```

Any uncaught exception raised in a fiber will be
[propagated]((exception-handling.md)) to its parent, and potentially further up
the fiber hierarchy, all the way to the main fiber:

```ruby
parent = spin do
  child = spin do
    raise 'foo'
  end
  sleep
end

sleep
# the exception will be propagated from the child fiber to the parent fiber,
# and from the parent fiber to the main fiber, which will cause the program to
# abort.
```

In addition, fibers can communicate with each other using message passing,
turning them into autonomous actors in a highly concurrent environment. Message
passing is in many ways a superior way to pass data between concurrent entities,
obviating the need to synchronize access to shared resources:

```ruby
writer = spin do
  while (write_request = receive)
    do_write(write_request)
  end
end
...
writer << { stamp: Time.now, value: rand }
```

## Higher-Order Concurrency Constructs

Polyphony also provides several methods and constructs for controlling multiple
fibers. Methods like `cancel_after` and `move_on_after` allow interrupting a
fiber that's blocking on any arbitrary operation.

Cancel scopes \(borrowed from the brilliant Python library
[Trio](https://trio.readthedocs.io/en/stable/)\) allows cancelling ongoing
operations for any reason with more control over cancelling behaviour.

Some other constructs offered by Polyphony:

* `Mutex` - a mutex used to synchronize access to a single shared resource.
* `ResourcePool` - used for synchronizing access to a limited amount of shared 
  resources, for example a pool of database connections.

* `Throttler` - used for throttling repeating operations, for example throttling
  access to a shared resource, or throttling incoming requests.

## A Compelling Concurrency Solution for Ruby

> The goal of Ruby is to make programmers happy.

— Yukihiro “Matz” Matsumoto

Polyphony's goal is to make programmers even happier by offering them an easy
way to write concurrent applications in Ruby. Polyphony aims to show that Ruby
can be used for developing sufficiently high-performance applications, while
offering all the advantages of Ruby, with source code that is easy to read and
understand.
