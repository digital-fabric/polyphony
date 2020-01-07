# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'
Exception.__disable_sanitized_backtrace__ = true

puts 'going to sleep...'
move_on_after(1) do
  sleep 60
  puts 'woke up'
end

puts 'going to sleep...'
move_on_after(0.5) do
  t0 = Time.now
  sleep(60)
ensure
  puts 'woke up'
end

puts 'going to sleep...'
value = move_on_after(1, with_value: :bar) { sleep 60 }
puts "got value #{value.inspect}"
