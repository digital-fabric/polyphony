---
layout: page
title: Home
nav_order: 1
description: Lorem ipsum
permalink: /
---

# Polyphony - fine-grained concurrency for Ruby

> Polyphony \| pəˈlɪf\(ə\)ni \|
> 1. _Music_ the style of simultaneously combining a number of parts, each
>    forming an individual melody and harmonizing with each other.
> 2. _Programming_ a Ruby gem for concurrent programming focusing on performance
>    and developer happiness.

Polyphony is a library for building concurrent applications in Ruby. Polyphony
harnesses the power of [Ruby fibers](https://ruby-doc.org/core-2.5.1/Fiber.html)
to provide a cooperative, sequential coroutine-based concurrency model. Under
the hood, Polyphony uses [libev](https://github.com/enki/libev) as a
high-performance event reactor that provides timers, I/O watchers and other
asynchronous event primitives.

## Focused on Developer Happiness

Polyphony is designed to make concurrent Ruby programming feel natural and
fluent. Polyphony reduces the boilerplate usually associated with concurrent
programming, and introduces concurrency primitives that are easy to use, easy to
understand, and above all idiomatic.

## Optimized for High Performance

Polyphony offers high performance for I/O bound Ruby apps. Distributing
concurrent tasks over fibers, instead of threads or processes, minimizes memory
consumption and reduces the cost of context-switching.

## Designed for Interoperability

Polyphony makes it possible to use normal Ruby built-in classes like `IO`, and
`Socket` in a concurrent multi-fiber environment. Polyphony takes care of
context-switching automatically whenever a blocking call like `Socket#accept`,
`IO#read` or `Kernel#sleep` is issued.

## A Growing Ecosystem

Polyphony includes a full-blown HTTP server implementation with integrated
support for HTTP 1, HTTP 2 and WebSockets, TLS/SSL termination, automatic
ALPN protocol selection, and body streaming. Polyphony also includes fiber-aware
extensions for PostgreSQL and Redis. More databases and services are forthcoming.

## Features

* Co-operative scheduling of concurrent tasks using Ruby fibers.
* High-performance event reactor for handling I/O events and timers.
* Natural, sequential programming style that makes it easy to reason about
  concurrent code.
* Abstractions and constructs for controlling the execution of concurrent code:
  supervisors, cancel scopes, throttling, resource pools etc.
* Code can use native networking classes and libraries, growing support for
  third-party gems such as `pg` and `redis`.
* Use stdlib classes such as `TCPServer` and `TCPSocket` and `Net::HTTP`.
* Competitive performance and scalability characteristics, in terms of both
  throughput and memory consumption.

## Prior Art

Polyphony draws inspiration from the following, in no particular order:

* [nio4r](https://github.com/socketry/nio4r/) and
  [async](https://github.com/socketry/async) (Polyphony's C-extension code is
  largely a spinoff of
  [nio4r's](https://github.com/socketry/nio4r/tree/master/ext))
* The [go scheduler](https://www.ardanlabs.com/blog/2018/08/scheduling-in-go-part2.html)
* [EventMachine](https://github.com/eventmachine/eventmachine)
* [Trio](https://trio.readthedocs.io/)
* [Erlang supervisors](http://erlang.org/doc/man/supervisor.html) (and actually,
  Erlang in general)

## Going further

To learn more about using Polyphony to build concurrent applications, read the
technical overview below, or look at the [included
examples](https://github.com/digital-fabric/polyphony/tree/9e0f3b09213156bdf376ef33684ef267517f06e8/examples/README.md).
A thorough reference is forthcoming.

## Contributing to Polyphony

Issues and pull requests will be gladly accepted. Please use the [Polyphony git
repository](https://github.com/digital-fabric/polyphony) as your primary point
of departure for contributing.