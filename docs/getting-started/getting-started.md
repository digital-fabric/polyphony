# Installing

## Installing

```bash
$ gem install polyphony
```

## Tutorial

## An echo server in Polyphony

Let's now examine how networking is done using Polyphony. Here's a bare-bones echo server written using Polyphony:

```ruby
require 'polyphony'

server = TCPServer.open(1234)
while client = server.accept
  spin do
    while (data = client.gets)
      client << data
    end
  end
end
```

This example demonstrates several features of Polyphony:

* The code uses the native `TCPServer` class from Ruby's stdlib, to setup a TCP

  server. The result of `server.accept` is also a native `TCPSocket` object.

  There are no wrapper classes being used.

* The only hint of the code being concurrent is the use of `Kernel#spin`,

  which starts a new coprocess on a dedicated fiber. This allows serving

  multiple clients at once. Whenever a blocking call is issued, such as

  `#accept` or `#read`, execution is _yielded_ to the event reactor loop, which 

  will resume only those coprocesses which are ready to be resumed.

* Exception handling is done using the normal Ruby constructs `raise`, `rescue`

  and `ensure`. Exceptions never go unhandled \(as might be the case with Ruby

  threads\), and must be dealt with explicitly. An unhandled exception will by

  default cause the Ruby process to exit.

