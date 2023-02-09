# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'
require 'polyphony/core/debug'

Exception.__disable_sanitized_backtrace__ = true

puts '----- start await example ------'
sleeper = spin do
  puts 'going to sleep'
  sleep 1
  puts 'woke up'
end

# One way to synchronize fibers is by using `Fiber#await`, which blocks
# until the fiber has finished running or has been interrupted.
waiter = spin do
  puts 'waiting for fiber to terminate'
  sleeper.await
  puts 'done waiting'
end

trace :before_await

sleep 2
waiter.await
trace :after_await
