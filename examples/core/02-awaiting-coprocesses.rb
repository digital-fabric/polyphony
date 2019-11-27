# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/auto_run'

sleeper = spin do
  puts 'going to sleep'
  sleep 1
  puts 'woke up'
end

# One way to synchronize coprocesses is by using `Coprocess#await`, which blocks
# until the coprocess has finished running or has been interrupted.
waiter = spin do
  puts 'waiting for coprocess to terminate'
  sleeper.await
  puts 'done waiting'
end
