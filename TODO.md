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

- async connect etc: look at https://github.com/socketry/async-postgres
- connection pool
- specify connection using URL
- support for SSL

## Redis

- support for sentinel:
  https://redis.io/topics/sentinel
  https://github.com/redis/redis-rb#sentinel-support
- support for SSL
- specify connection using URL