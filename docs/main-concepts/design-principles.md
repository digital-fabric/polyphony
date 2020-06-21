---
layout: page
title: The Design of Polyphony
nav_order: 5
parent: Main Concepts
permalink: /main-concepts/design-principles/
prev_title: Extending Polyphony
---
# The Design of Polyphony 

Polyphony is a new gem that aims to enable developing high-performance
concurrent applications in Ruby using a fluent, compact syntax and API.
Polyphony enables fine-grained concurrency - the splitting up of operations into
a large number of concurrent tasks, each concerned with small part of the whole
and advancing at its own pace. Polyphony aims to solve some of the problems
associated with concurrent Ruby programs using a novel design that sets it apart
from other approaches currently being used in Ruby.

## Origins

The Ruby core language (at least in its MRI implementation) currently provides
two main constructs for performing concurrent work: threads and fibers. While
Ruby threads are basically wrappers for OS threads, fibers are essentially
continuations, allowing pausing and resuming distinct computations. Fibers have
been traditionally used mostly for implementing enumerators and generators.

In addition to the core Ruby concurrency primitives, some Ruby gems have been
offering an alternative solution to writing concurrent Ruby apps, most notably
[EventMachine](https://github.com/eventmachine/eventmachine/), which implements
an event reactor and offers an asynchronous callback-based API for writing
concurrent code.

In the last couple of years, however, fibers have been receiving more attention
as a possible constructs for writing concurrent programs. In particular, the
[Async](https://github.com/socketry/async) framework, created by [Samuel
Williams](https://github.com/ioquatix), offering a comprehensive set of
libraries, employs fibers in conjunction with an event reactor provided by the
[nio4r](https://github.com/socketry/nio4r) gem, which wraps the C
library [libev](http://software.schmorp.de/pkg/libev.html).

In addition, recently some effort was undertaken to provide a way to
[automatically switch between fibers](https://bugs.ruby-lang.org/issues/13618)
whenever a blocking operation is performed, or to [integrate a fiber
scheduler](https://bugs.ruby-lang.org/issues/16786) into the core Ruby code.

Nevertheless, while work is being done to harness fibers for providing a better
way to do concurrency in Ruby, fibers remain a mistery for most Ruby
programmers, a perplexing unfamiliar corner right at the heart of Ruby.

## Design Principles

Polyphony started as an experiment, but over about two years of slow, jerky
evolution turned into something I'm really excited to share with the Ruby
community. Polyphony's design is both similar and different than the projects
mentioned above.

Polyphony today as nothing like the way it began. A careful examination of the
[CHANGELOG](https://github.com/digital-fabric/polyphony/blob/master/CHANGELOG.md)
would show how Polyphony explored not only different event reactor designs, but
also different API designs incorporating various concurrent paradigms such as
promises, async/await, fibers, and finally structured concurrency. 

While Polyphony, like nio4r or EventMachine, uses an event reactor to turn
blocking operations into non-blocking ones, it completely embraces fibers and in
fact does not provide any callback-based APIs. Furthermore, Polyphony provides
fullblown fiber-aware implementations of blocking operations, such as
`read/write`, `sleep` or `waitpid`, instead of just event watching primitives.

Throughout the development process, it was my intention to create a programming
interface that would make highly-concurrent 







a single Ruby process may spin up millions of
concurrent fibers.

, by utilizing Ruby fibers together with the
[libev](http://pod.tst.eu/http://cvs.schmorp.de/libev/ev.pod) event reactor
library. Polyphony's design is based on the following principles:

- Polyphony's concurrency model should feel "baked-in". The API should allow
  concurrency with minimal effort. Polyphony should facilitate writing both
  large apps and small scripts with as little boilerplate code as possible.
  There should be no calls to initialize the event reactor, or other ceremonial
  code:

  ```ruby
  require 'polyphony'

  # start 10 fibers, each sleeping for 1 second
  10.times { spin { sleep 1 } }

  puts 'going to sleep now'
  # wait for other fibers to terminate
  suspend
  ```

- Blocking operations should yield to other concurrent tasks without any
  decoration or wrapper APIs. This means no `async/await` notation, and no
  async callback-style APIs.

  ```ruby
  # in Polyphony, I/O ops might block the current fiber, but implicitly yield to
  # other concurrent fibers:
  clients.each { |client|
    spin { client.puts 'Elvis has left the chatroom' }
  }
  ```

- Concurrency primitives should be accessible using idiomatic Ruby techniques
  (blocks, method chaining...) and should feel as much as possible "part of the
  language". The resulting API is based more on methods and less on classes,
  for example `spin` or `move_on_after`, leading to a coding style that is both
  more compact and more legible:

  ```ruby
  fiber = spin {
    move_on_after(3) {
      do_something_slow
    }
  }
  ```

- Breaking up operations into 

- Polyphony should embrace Ruby's standard `raise/rescue/ensure` exception
  handling mechanism. Exception handling in a highly concurrent environment
  should be robust and foolproof:

  ```ruby
  cancel_after(0.5) do
    puts 'going to sleep'
    sleep 1
    # this will not be printed
    puts 'wokeup'
  ensure
    # this will be printed
    puts 'done sleeping'
  end
  ```

- Concurrency primitives should allow creating higher-order concurrent 
  constructs through composition. This is done primarily through supervisors and
  cancel scopes:

  ```ruby
  # wait for multiple fibers
  supervise { |s|
    clients.each { |client|
      s.spin { client.puts 'Elvis has left the chatroom' }
    }
  }
  ```

- The entire design should embrace fibers. There should be no callback-based
  asynchronous APIs.

- Use of extensive monkey patching of Ruby core modules and classes such as
  `Kernel`, `Fiber`, `IO` and `Timeout`. This allows porting over non-Polyphony
  code, as well as using a larger part of stdlib in a concurrent manner, without
  having to use custom non-standard network classes or other glue code.

  ```ruby
  require 'polyphony'

  # use TCPServer from Ruby's stdlib
  server = TCPServer.open('127.0.0.1', 1234)
  while (client = server.accept)
    spin do
      while (data = client.gets)
        client.write('you said: ', data.chomp, "!\n")
      end
    end
  end
  ```

- Development of techniques and tools for converting callback-based APIs to
  fiber-based ones.
