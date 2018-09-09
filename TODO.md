## Nicer interface for watching i/o:

```ruby
Reactor.watch(socket, :rw) do |readable, writable|
  if readable
    ...
  end
  if writable
    ...
  end
end
```

Or maybe:

```ruby
Reactor.watch(socket,
  read: -> { ... },
  write: -> { ... }
)
```

## A way to test async/await code

See examples/reactor/sync.rb

## HTTP/HTTPS client

## ThreadPool that runs code and returns promise

```ruby
ThreadPool = import('nuclear/thread_pool')

async do
  result = await ThreadPool.spawn { fib(100) }
```

## Code reogranisation

- Split into multiple gems:

  `nuclear.core` - includes reactor, async, io, net, line_reader
  `nuclear.http` - http server/client
  `nuclear.redis` - redis client
  `nuclear.pg` - pg client

- Move ALPN code from http module to net module