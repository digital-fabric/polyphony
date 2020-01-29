# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

Exception.__disable_sanitized_backtrace__ = true

f = spin_loop {
  snooze
}

puts 'going to sleep...'
sleep 1
puts 'woke up'
f.stop

