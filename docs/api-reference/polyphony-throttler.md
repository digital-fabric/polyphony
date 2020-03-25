---
layout: page
title: Polyphony::Throttler
parent: API Reference
permalink: /api-reference/polyphony-throttler/
---
# Polyphony::Throttler

`Polyphony::Throttler` implements general purpose operation throttling, or rate
limiting. A `Polyphony::Throttler` instance may be used to limit the rate of an
arbitrary operation in a single fiber, or across multiple fibers. For example,
an HTTP server can limit the number of requests per second across for each
client, or for all clients.

A throttler is invoked using its `#call` method, e.g.:

```ruby
# throttle rate: one per second
throttler = Polyphony::Throttler.new(1)

10.times do |i|
  spin_loop { throttler.call { p [i, Time.now] } }
end
```

If many throttler instances are created over the application's lifetime, they
should be stopped using the `#stop` method in order to prevent memory leaks.
This is best done using an `ensure` block:

```ruby
def start_server
  throttler = Polyphony::Throttler.new(1000)
  MyServer.start do |req|
    throttler.call { handle_request(req) }
  end
ensure
  throttler.stop
end
```

## Instance methods

### #initialize(rate)<br>#initialize(interval: interval)<br>#initialize(rate: rate)

Initializes the throttler with the given rate. The rate can be specified either
as a number signifying the maximum rate per second, or as a keyword argument. If
the rate is specified using the `interval:` keyword argument, the value given is
the minimum interval between consecutive invocations.

```ruby
# These are all equivalent
Polyphony::Throttler.new(10)
Polyphony::Throttler.new(rate: 10)
Polyphony::Throttler.new(interval: 0.1)
```

### #call({ block }) → object

Invokes the throttler with the given block. This method will sleep for an
interval of time required to throttle the execution of the given block. The
return value is the return value of the given block.

### #stop → throttler

Stops the timer associated with the throttler. This method should be called when
the throttler is no longer needed. This is best done from an `ensure` block.

```ruby
def start_server
  throttler = Polyphony::Throttler.new(1000)
  MyServer.start do |req|
    throttler.call { handle_request(req) }
  end
ensure
  throttler.stop
end
```