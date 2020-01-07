# Polyphony - Easy Concurrency for Ruby

> Polyphony \| pəˈlɪf\(ə\)ni \|
> 1. _Music_ the style of simultaneously combining a number of parts, each forming an individual melody and harmonizing with each other.
> 2. _Programming_ a Ruby gem for concurrent programming focusing on performance and developer happiness.

Polyphony is a library for building concurrent applications in Ruby. Polyphony harnesses the power of [Ruby fibers](https://ruby-doc.org/core-2.5.1/Fiber.html) to provide a cooperative, sequential coprocess-based concurrency model. Under the hood, Polyphony uses [libev](https://github.com/enki/libev) as a high-performance event reactor that provides timers, I/O watchers and other asynchronous event primitives.

Polyphony makes it possible to use normal Ruby built-in classes like `IO`, and `Socket` in a concurrent fashion without having to resort to threads. Polyphony takes care of context-switching automatically whenever a blocking call like `Socket#accept` or `IO#read` is issued.

## Features

* **Full-blown, integrated, high-performance HTTP 1 / HTTP 2 / WebSocket server with TLS/SSL termination, automatic ALPN protocol selection, and body streaming**.
* Co-operative scheduling of concurrent tasks using Ruby fibers.
* High-performance event reactor for handling I/O events and timers.
* Natural, sequential programming style that makes it easy to reason about concurrent code.
* Abstractions and constructs for controlling the execution of concurrent code: coprocesses, supervisors, cancel scopes, throttling, resource pools etc.
* Code can use native networking classes and libraries, growing support for third-party gems such as `pg` and `redis`.
* Use stdlib classes such as `TCPServer` and `TCPSocket` and `Net::HTTP`.
* HTTP 1 / HTTP 2 client agent with persistent connections.
* Competitive performance and scalability characteristics, in terms of both throughput and memory consumption.

## Prior Art

Polyphony draws inspiration from the following, in no particular order:

* [nio4r](https://github.com/socketry/nio4r/) and [async](https://github.com/socketry/async) (Polyphony's C-extension code is largely a spinoff of [nio4r's](https://github.com/socketry/nio4r/tree/master/ext))
* [EventMachine](https://github.com/eventmachine/eventmachine)
* [Trio](https://trio.readthedocs.io/)
* [Erlang supervisors](http://erlang.org/doc/man/supervisor.html) (and actually, Erlang in general)

## Going further

To learn more about using Polyphony to build concurrent applications, read the technical overview below, or look at the [included examples](https://github.com/digital-fabric/polyphony/tree/9e0f3b09213156bdf376ef33684ef267517f06e8/examples/README.md). A thorough reference is forthcoming.

## Contributing to Polyphony

Issues and pull requests will be gladly accepted. Please use the git repository at https://github.com/digital-fabric/polyphony as your primary point of departure for contributing.