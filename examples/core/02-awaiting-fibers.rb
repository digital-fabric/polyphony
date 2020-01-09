# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

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

waiter.await