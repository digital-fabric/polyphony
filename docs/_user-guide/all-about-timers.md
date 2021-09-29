---
layout: page
title: All About Timers
nav_order: 1
parent: User Guide
permalink: /user-guide/all-about-timers/
---
# All About Timers

Timers form a major part of writing dynamic concurrent programs. They allow
programmers to create delays and to perform recurring operations with a
controllable frequency. Crucially, they also enable the implementation of
timeouts, which are an important aspect of concurrent programming.

## Sleeping

Sometimes, your code needs to wait for a certain period of time. For example,
implementing a retry mechanism for failed HTTP requests might involve waiting
for a few seconds before retrying. Polyphony patches the `Kernel#sleep` method
to be fiber-aware, that is to yield control of execution while waiting for a
timer to elapse.

```ruby
# This is a naive retry implementation
def fetch(url)
  fetch_url(url)
rescue
  sleep 1
  retry
end
```

## Sleeping Forever

The `#sleep` method can also be used to sleep forever, if no argument is given:

```ruby
puts "Go to sleep"
sleep
puts "Woke up" # this line will not be executed
```

The `#sleep` forever call can be used for example in the main fiber when we do
all our work in other fibers, since once the main fiber terminates the program
exits.

## Doing Work Later

While `#sleep` allows you to block execution of the current fiber, sometimes you
want to perform some work later, while not blocking the current fiber. This is done simply by spinning off another fiber:

```ruby
do_some_stuff
spin do
  sleep 3
  do_stuff_later
end
do_some_more_stuff
```

## Using timeouts

Polyphony provides the following global methods for using timeouts:

- `#move_on_after` - used for cancelling an operation after a certain period of time without raising an exception:

  ```ruby
  move_on_after 1 do
    sleep 60
  end
  ```

  This method also takes an optional return value argument:

  ```ruby
  move_on_after 1, with_value: 'bar' do
    sleep 60
    'foo'
  end #=> 'bar'
  ```

- `#cancel_after` - used for cancelling an operation after a certain period of time with a `Cancel` exception:

  ```ruby
  cancel_after 1 do
    sleep 60
  end #=> raises Cancel
  ```

Polyphony also provides a fiber-aware version of the core Ruby `Timeout` API, which may be used directly or indirectly to interrupt blocking operations.

## Using Raw Timers

Polyphony implements timers through the `Gyro::Timer` class, which encapsulates
libev timer watchers. Using `Gyro::Timer` you can create both one-time and
recurring timers:

```ruby
# Create a one-time timer
one_time = Gyro::Timer.new(1, 0)

# Create a recurring timer
recurring = Gyro::Timer.new(0.5, 1.5)
```

Once your timer is created, you can wait for it using the `#await` method:

```ruby
def delay(duration)
  timer = Gyro::Timer.new(duration, 0)
  timer.await
end
```

Waiting for the timer will *block* the current timer. This means that if you
want to do other work while waiting for the timer, you need to put it on a
different fiber:

```ruby
timer = Gyro::Timer.new(3, 0)
spin {
  sleep 3
  do_something_else
}
do_blocking_operation
```
