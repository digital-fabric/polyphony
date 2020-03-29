---
layout: page
title: Gyro::Timer
parent: API Reference
permalink: /api-reference/gyro-timer/
---
# Gyro::Timer

`Gyro::Timer` encapsulates a libev [timer
watcher](http://pod.tst.eu/http://cvs.schmorp.de/libev/ev.pod#code_ev_timer_code_relative_and_opti),
allowing waiting a certain amount of time before proceeding with an operation.
Watchers can be either one-time timers or recurring timers. The Polyphony API
provides various APIs that use timer watchers for timeouts, throttled
operations, and sleeping.

## Instance methods

### #await → object

Blocks the current thread until the timer has elapsed. For recurrent timers,
`#await` will block until the next timer period has elapsed, as specified by the
`repeat` argument given to `#initialize`.

### #initialize(after, repeat)

Initializes the watcher instance. The `after` argument gives the time duration
in seconds before the timer has elapsed. The `repeat` argument gives the time
period for recurring timers, or `0` for non-recurring timers.

### #stop

Stops an active recurring timer. Recurring timers stay active (from the point of
view of the event loop) even after the timer period has elapsed. Calling `#stop`
marks the timer as inactive and cleans up associated resources. This should
normally be done inside an `ensure` block:

```ruby
def repeat(period)
  timer = Gyro::Timer.new(period, period)
  loop do
    timer.await
    yield
  end
ensure
  timer.stop
end

repeat(10) { puts Time.now }
```

There's no need to call `#stop` for non-recurring timers.
