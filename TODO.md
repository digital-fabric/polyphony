## Simpler spawning of tasks

Tasks are basically just procs that run on separate fibers, and can
suspend and resume execution.

Spawning a task is done from the root fiber. If a task is spawned not from the
root fiber, it will be spawned using a timer.

```ruby
# spawn a new asynchronous task, and return the fiber used
async { ... }
```

This obviates the need for `async!`.

A task can be cancelled by resuming its fiber with a `Cancelled` or `MoveOn`
exception. We do need a way to cancel nested asyncs, e.g.:

```ruby
async {
  move_on_after(60) do |scope|
    task1 = async { ... }
    task2 = async { ... }

    # add more tasks to scope, so they too will be cancelled
    scope << task1
    scope << task2

    # if we only start sub-tasks, maybe we can wait for the scope's timeout
    await scope.timeout
  end
}
```

## Happy eyeballs code with planned changes:

```ruby
def open_tcp_socket(hostname, port, max_wait_time: 0.25)
  targets = await Net.getaddrinfo(hostname, port, :STREAM)
  winning_socket = nil

  await async_cluster do |cluster|
    previous_try = nil
    targets.each do |t|
      await sleep max_wait_time if previous_try
      previous_try = async { try_connect(cluster, t) }
      cluster << previous_try
    end
  end
end

def try_connect(cluster, target)
  socket = await Net.connect(*target)
  cluster.move_on(socket)
end

# Let's try it out:
async do
  puts(await open_tcp_socket("debian.org", "https"))
end
```

## Going forward

- make async/await methods global methods in `Kernel` module
- rewrite Promise as Task
- add cancel scope implementation
- rewrite I/O class:
  - get rid of stream class
  - get rid of callback API
- rewrite Net class:
  - get rid of callback API

## Error backtracing

*exception.rb*
```ruby
require 'modulation'
Nuclear = import('../../lib/nuclear')
Nuclear.interval(1) { raise 'hi!' }
```

Exception: hi
examples/timers/exception.rb:3:in `block in <main>'
/Users/sharon/repo/nuclear/lib/nuclear/core.rb:50:in `run'
/Users/sharon/repo/nuclear/lib/nuclear/ev.rb:xxx:in `interval'
examples/timers/exception.rb:3:in `<main>'

## Net

- rename to TCP
- add support for reuse_addr
- use plain `Socket` instance instead of `TCPServer`
- use `#bind` and `#listen` instead of implicit listen in `TCPServer.new`

## Testing

- test EV layer: `EV.run`, watchers: IO, timer, signal (and `Core.trap`), async
- test promises / async constructs: async/await, generator, pulse etc.
- test stream / IO
- test TCP server / client
- test thread / thread_pool modules

## HTTP

- integrate `http_parser.rb` gem, with better suited API:
  - parser should provide `Request`-compatible API:
  - go for minimum of allocations, use symbols as hash keys for 

- client
- rack adapter
- binary for running rack apps

## PG

- specify connection using URL
- support for SSL

## Redis

- support for sentinel:
  https://redis.io/topics/sentinel
  https://github.com/redis/redis-rb#sentinel-support
- support for SSL
- specify connection using URL

## UDP socket

```ruby
socket = UDP.new

socket.on(:message) do |msg, info|
  puts "got #{msg} from #{info[:address]}:#{info[:port]}"
  socket.send("reply", **info)
end

socket.on(:listen) { puts "listening..." }

socket.bind(1234) # localhost port 1234
```

## DNS client

```ruby
ip_address = await DNS.lookup('google.com', 'A')
```

Prior art:

- https://github.com/alexdalitz/dnsruby
- https://github.com/eventmachine/eventmachine/blob/master/lib/em/resolver.rb
- https://github.com/gmodarelli/em-resolv-replace/blob/master/lib/em-dns-resolver.rb
- https://github.com/socketry/async-dns

### DNS server

```ruby
Server = import('../../lib/nuclear/dns/server')

server = Server.new do |transaction|
  puts "got query from #{transaction.info[:client_ip_address]}"
  transaction.questions.each do |q|
    respond(transaction, q[:domain], q[:resource_class])
  end
end

server.listen(port: 5300)
puts "listening on port 5300"
```

Prior art:

- https://github.com/socketry/async-dns
