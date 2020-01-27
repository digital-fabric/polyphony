---
layout: page
title: Design Principles
nav_order: 1
parent: Technical Overview
permalink: /technical-overview/design-principles/
prev_title: A Gentle Introduction to Polyphony
next_title: Concurrency the Easy Way
---
# Design Principles

Polyphony was created in order to enable creating high-performance concurrent
applications in Ruby, by utilizing Ruby fibers together with the
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
  # in Polyphony, I/O ops block the current fiber, but implicitly yield to other
  # concurrent fibers:
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

- Polyphony should embrace Ruby's standard `raise/rescue/ensure` exception
  handling mechanism:

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
