# Polyphony - Fine-Grained Concurrency for Ruby


[![Gem Version](https://badge.fury.io/rb/polyphony.svg)](http://rubygems.org/gems/polyphony)
[![Modulation Test](https://github.com/digital-fabric/polyphony/workflows/Tests/badge.svg)](https://github.com/digital-fabric/polyphony/actions?query=workflow%3ATests)
[![MIT licensed](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/digital-fabric/polyphony/blob/master/LICENSE)

[DOCS](https://digital-fabric.github.io/polyphony/) |
[EXAMPLES](examples)

> Polyphony \| pəˈlɪf\(ə\)ni \|
> 1. _Music_ the style of simultaneously combining a number of parts, each
>    forming an individual melody and harmonizing with each other.
> 2. _Programming_ a Ruby gem for concurrent programming focusing on performance
>    and developer happiness.

## What is Polyphony

Polyphony is a library for building concurrent applications in Ruby. Polyphony
harnesses the power of [Ruby fibers](https://ruby-doc.org/core-2.5.1/Fiber.html)
to provide a cooperative, sequential coroutine-based concurrency model. Under
the hood, Polyphony uses [libev](https://github.com/enki/libev) as a
high-performance event reactor that provides timers, I/O watchers and other
asynchronous event primitives.

## Features

* Co-operative scheduling of concurrent tasks using Ruby fibers.
* High-performance event reactor for handling I/O events and timers.
* Natural, sequential programming style that makes it easy to reason about
  concurrent code.
* Abstractions and constructs for controlling the execution of concurrent code:
  supervisors, cancel scopes, throttling, resource pools etc.
* Code can use native networking classes and libraries, growing support for
  third-party gems such as `pg` and `redis`.
* Use stdlib classes such as `TCPServer`, `TCPSocket` and
  `OpenSSL::SSL::SSLSocket`.
* Competitive performance and scalability characteristics, in terms of both
  throughput and memory consumption.

## Documentation

The complete documentation for Polyphony could be found on the
[Polyphony website](https://digital-fabric.github.io/polyphony).

## Contributing to Polyphony

Issues and pull requests will be gladly accepted. Please use the [Polyphony git
repository](https://github.com/digital-fabric/polyphony) as your primary point
of departure for contributing.
