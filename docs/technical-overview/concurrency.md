# Concurrency the Easy Way

Concurrency is a major consideration for the modern programmer. Nowadays
applications and digital platforms are expected to do multiple things at once:
serve multiple clients, process multiple background jobs, talk to multiple
external services. Concurrency is the property of our programming environment
allowing us to schedule and control multiple ongoing operations.

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
pre-emptive concurrency, like threads and processes), offers many advantages,
especially for applications that are
[I/O bound](https://en.wikipedia.org/wiki/I/O_bound). Fibers are very
lightweight (starting at about 20KB), can be switched faster than threads or
processes, and literally millions of them can be created on a single system -
the only limiting factor is available memory.

Polyphony takes Ruby's fibers and adds a way to schedule and switch between
fibers automatically whenever a blocking operation is started, such as waiting
for a TCP connection to be established, or waiting for an I/O object to be
readable, or waiting for a timer to elapse. In addition, Polyphony patches the
stock Ruby classes to support its concurrency model, letting developers use all
of Ruby's stdlib, for example `Net::HTTP` and `Mail` while reaping the benefits
of lightweight, highly performant, fiber-based concurrency.

## Coprocesses - Polyphony's basic unit of concurrency

While stock Ruby fibers can be used with Polyphony without any problem, the API
they provide is very basic, and necessitates writing quite a bit of boilerplate
code whenever they need to be synchronized, interrupted or otherwise controlled.
For this reason, Polyphony provides entities that encapsulate fibers and provide
a richer API, making it easier to compose concurrent applications employing
fibers.

A coprocess can be thought of as a fiber with enhanced powers. It makes sure any
exception raised while it's running is
[handled correctly](./exception-handling.md). It can be interrupted or 
`await`ed (just like `Thread#join`). It provides methods for controlling its
execution. Moreover, coprocesses can pass messages between themselves, turning
them into autonomous actors in a fine-grained concurrent environment.

## Higher-Order Concurrency Constructs

Polyphony also provides several methods and constructs for controlling multiple
coprocesses. Methods like `cancel_after` and `move_on_after` allow interrupting
a coprocess that's blocking on any arbitrary operation.

Cancel scopes (borrowed from the brilliant Python library
[Trio](https://trio.readthedocs.io/en/stable/)) allows cancelling ongoing
operations for any reason with more control over cancelling 
behaviour.

Supervisors allow controlling multiple coprocesses. They offer enhanced
exception handling and can be nested to create complex supervision trees ala
[Erlang](https://adoptingerlang.org/docs/development/supervision_trees/).

Some other constructs offered by Polyphony:

- `Mutex` - a mutex used to synchronize access to a single shared resource.
- `ResourcePool` - used for synchronizing access to a limited amount of shared 
  resources, for example a pool of database connections.
- `Throttler` - used for throttling repeating operations, for example throttling
  access to a shared resource, or throttling incoming requests.
