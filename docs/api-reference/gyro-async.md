---
layout: page
title: Gyro::Async
parent: API Reference
permalink: /api-reference/gyro-async/
---
# Gyro::Async

`Gyro::Async` encapsulates a libev [async
watcher](http://pod.tst.eu/http://cvs.schmorp.de/libev/ev.pod#code_ev_async_code_how_to_wake_up_an),
allowing thread-safe synchronisation and signalling. `Gyro::Async` watchers are
used both directly and indirectly in Polyphony to implement
[queues](../gyro-queue/), await fibers and threads, and auxiliary features such
as [thread pools](../polyphony-threadpool/).

A `Gyro::Async` watcher instance is shared across two or more fibers (across one
or more threads), where one fiber waits to be signalled by calling
`Gyro::Async#await`, and one or more other fibers do the signalling by calling
`Gyro::Async#signal`:

```ruby
async = Gyro::Async.new
spin do
  sleep 1
  async.signal
end

async.await
```

The signalling of async watchers is compressed, which means that multiple
invocations of `Gyro::Async#signal` before the event loop can continue will
result the watcher being signalled just a single time.

In addition to signalling, the async watcher can also be used to transfer an
arbitrary value to the awaitng fiber. See `#signal` for an example.

## Instance methods

### #await → object

Blocks the current thread until the watcher is signalled.

### #initialize

Initializes the watcher instance.

### #signal(value = nil) → async

Signals the watcher, causing the fiber awaiting the watcher to become runnable
and be eventually resumed with the given value.

```ruby
async = Gyro::Async.new
spin { async.signal('foo') }
async.await #=> 'foo'
```
