---
layout: page
title: Global API
nav_order: 2
parent: API Reference
permalink: /api-reference/global/
---
# Global API

The global Polyphony API is designed to feel almost like a part of the Ruby
runtime. The global API contains multiple methods for creating and controlling
fibers, as well as miscellaneous methods for dealing with timers and other
events, with minimal boilerplate. The API is implemented as a module included in
the `Object` class, allowing access from any receiver.

### #after(interval, { block }) → fiber

Run the given block after the given time interval (specified in seconds). This
method spins up a separate fiber that will sleep for the given interval, then
run the given block.

```ruby
f = spin { do_some_big_work }
after(1) { f.stop }
f.await
```

### #cancel_after(interval, { block }) → object

Run the given block, cancelling it after the given time interval by raising a
`Polyphony::Cancel` exception. If uncaught, the exception will be propagated.

```ruby
spin do
  cancel_after(3) { do_some_work }
rescue Polyphony::Cancel
  puts "work was cancelled"
end
```

### #every(interval, { block }) → object

Runs the given block repeatedly, at the given time interval. This method will
block until an exception is raised.

```ruby
every(3) do
  puts "I'm still alive"
end
```

### #move_on_after(interval, with_value: nil, { block }) → object

Run the given block, interrupting it after the given time interval by raising a
`Polyphony::MoveOn` exception. The `with_value` keyword argument can be used to
set the value returned from the block if the timeout has elapsed.

```ruby
result = move_on_after(3, with_value: 'bar') { sleep 5; 'foo' }
result #=> 'bar'
```

### #receive → object

Shortcut for `Fiber.current.receive`

### #receive_pending → [*object]

Shortcut for `Fiber.current.receive_pending`

### #sleep(duration = nil) → fiber

Sleeps for the given duration.

### #spin(tag = nil, { block}) → fiber

Shortcut for `Fiber.current.spin`

### #spin_loop(tag = nil, rate: nil, &block) → fiber

Spins up a new fiber that runs the given block in a loop. If `rate` is given,
the loop is throttled to run `rate` times per second.

```ruby
# print twice a second
f = spin_loop(rate: 2) { puts 'hello world' }
sleep 2
f.stop
```

### #throttled_loop(rate, count: nil, &block) → object

Runs the given block in a loop at the given rate (times per second). If `count`
is given, the loop will be run for the specified number of times and then
returns. Otherwise, the loop is infinite (unless an exception is raised).

```ruby
# twice a second
throttled_loop(2) { puts 'hello world' }
```