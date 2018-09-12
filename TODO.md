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

This will require a fork of nio4r, which could possibly yield a significant
performance improvement. There's a lot of stuff there we don't need, and the
API in general is a bit clunky.

## HTTP

- client
- rack adapter
- binary for running rack apps

## ThreadPool that runs code and returns promise

```ruby
ThreadPool = import('nuclear/thread_pool')

async do
  result = await ThreadPool.spawn { fib(100) }
```

## PG

- specify connection using URL
- support for SSL

## Redis

- support for sentinel:
  https://redis.io/topics/sentinel
  https://github.com/redis/redis-rb#sentinel-support
- support for SSL
- specify connection using URL