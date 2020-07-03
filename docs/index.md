---
layout: page
title: Home
nav_order: 1
permalink: /
next_title: Installing Polyphony
---

# Polyphony - fine-grained concurrency for Ruby

Polyphony is a library for building concurrent applications in Ruby. Polyphony
implements a comprehensive
[fiber](https://ruby-doc.org/core-2.5.1/Fiber.html)-based concurrency model,
using [libev](https://github.com/enki/libev) as a high-performance event reactor
for I/O, timers, and other asynchronous events.

[Take the tutorial](getting-started/tutorial){: .btn .btn-blue .text-gamma }
[Main Concepts](main-concepts/concurrency/){: .btn .btn-green .text-gamma }
[FAQ](faq){: .btn .btn-green .text-gamma }
[Source code](https://github.com/digital-fabric/polyphony){: .btn .btn-purple .text-gamma target="_blank" }
{: .mt-6 .h-align-center }

## Focused on Developer Happiness

Polyphony is designed to make concurrent Ruby programming feel natural and
fluent. The Polyphony API is easy to use, easy to understand, and above all
idiomatic.

## Optimized for High Performance

Polyphony offers high performance for I/O bound Ruby apps. Distributing
concurrent operations over fibers, instead of threads or processes, minimizes
memory consumption and reduces the cost of context-switching.

## Designed for Interoperability

With Polyphony you can use any of the stock Ruby classes and modules like `IO`,
`Process`, `Socket` and `OpenSSL` in a concurrent multi-fiber environment. In
addition, Polyphony provides a structured model for exception handling that
builds on and enhances Ruby's exception handling system.

## A Growing Ecosystem

Polyphony includes a full-blown HTTP server implementation with integrated
support for HTTP 2, WebSockets, TLS/SSL termination and more. Polyphony also
provides fiber-aware adapters for connecting to PostgreSQL and Redis. More
adapters are being developed.

## Features

* Co-operative scheduling of concurrent tasks using Ruby fibers.
* High-performance event reactor for handling I/O events and timers.
* Natural, sequential programming style that makes it easy to reason about
  concurrent code.
* Abstractions and constructs for controlling the execution of concurrent code:
  supervisors, throttling, resource pools etc.
* Code can use native networking classes and libraries, growing support for
  third-party gems such as `pg` and `redis`.
* Use stdlib classes such as `TCPServer` and `TCPSocket` and `Net::HTTP`.
* Competitive performance and scalability characteristics, in terms of both
  throughput and memory consumption.

## Prior Art

Polyphony draws inspiration from the following, in no particular order:

* [nio4r](https://github.com/socketry/nio4r/) and
  [async](https://github.com/socketry/async) (Polyphony's C-extension code
  started as a spinoff of
  [nio4r's](https://github.com/socketry/nio4r/tree/master/ext))
* The [go scheduler](https://www.ardanlabs.com/blog/2018/08/scheduling-in-go-part2.html)
* [EventMachine](https://github.com/eventmachine/eventmachine)
* [Trio](https://trio.readthedocs.io/)
* [Erlang supervisors](http://erlang.org/doc/man/supervisor.html) (and actually,
  Erlang in general)

## Developer Resources

* [Tutorial](getting-started/tutorial)
* [Main Concepts](main-concepts/concurrency/)
* [User Guide](user-guide/all-about-timers/)
* [API Reference](api-reference/exception/)
* [Examples](https://github.com/digital-fabric/polyphony/tree/9e0f3b09213156bdf376ef33684ef267517f06e8/examples/README.md)

## Contributing to Polyphony

Issues and pull requests will be gladly accepted. Please use the [Polyphony git
repository](https://github.com/digital-fabric/polyphony) as your primary point
of departure for contributing.
