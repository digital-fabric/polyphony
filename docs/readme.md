# @title README

<img src="https://github.com/digital-fabric/polyphony/raw/master/docs/assets/polyphony-logo.png">

# Polyphony: Fine-Grained Concurrency for Ruby

<a href="http://rubygems.org/gems/polyphony">
  <img src="https://badge.fury.io/rb/polyphony.svg" alt="Ruby gem">
</a>
<a href="https://github.com/digital-fabric/polyphony/actions?query=workflow%3ATests">
  <img src="https://github.com/digital-fabric/polyphony/workflows/Tests/badge.svg" alt="Tests">
</a>
<a href="https://github.com/digital-fabric/polyphony/blob/master/LICENSE">
  <img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License">
</a>

> Polyphony \| pəˈlɪf\(ə\)ni \|
>
> 1. _Music_ the style of simultaneously combining a number of parts, each
>    forming an individual melody and harmonizing with each other.
>
> 2. _Programming_ a Ruby gem for concurrent programming focusing on performance
>    and developer happiness.

## What is Polyphony?

Polyphony is a library for building concurrent applications in Ruby. Polyphony
harnesses the power of [Ruby fibers](https://rubyapi.org/3.3/o/fiber) to provide
a cooperative, sequential coroutine-based concurrency model. Under the hood,
Polyphony uses [io_uring](https://unixism.net/loti/what_is_io_uring.html) or
[libev](https://github.com/enki/libev) to maximize I/O performance.

## Features

* Ruby fibers as the main unit of concurrency.
* [Structured concurrency](https://en.wikipedia.org/wiki/Structured_concurrency)
  coupled with robust exception handling.
* Message passing between fibers, even across threads!
* High-performance I/O using the core Ruby I/O classes and
  [io_uring](https://unixism.net/loti/what_is_io_uring.html) with support for
  {file:/docs/advanced-io.md advanced I/O patterns}.

## Usage

- {file:/docs/installation.md       Installation}
- {file:/docs/overview.md           Overview}
- {file:/docs/tutorial.md           Tutorial}
- {file:/docs/cancellation.md       All About Cancellation: How to Stop Concurrent Operations}
- {file:/docs/advanced-io.md        Advanced I/O with Polyphony}
- {file:/docs/cheat-sheet.md        Cheat-Sheet}
- {file:/docs/faq.md                FAQ}

## Technical Discussion

- {file:/docs/concurrency.md        Concurrency the Easy Way}
- {file:/docs/fiber-scheduling.md   How Fibers are Scheduled}
- {file:/docs/exception-handling.md Exception Handling}
- {file:/docs/extending.md          Extending Polyphony}
- {file:/docs/design-principles.md  Polyphony's Design}

## Examples

For examples of specific use cases you can consult the [bundled
examples](https://github.com/digital-fabric/polyphony/tree/master/examples) in
Polyphony's GitHub repository.

## Contributing to Polyphony

Issues and pull requests will be gladly accepted. Please use the [Polyphony git
repository](https://github.com/digital-fabric/polyphony) as your primary point
of departure for contributing.
