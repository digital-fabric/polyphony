# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

Exception.__disable_sanitized_backtrace__ = true

t = Thread.new {
  t0 = Time.now
  puts "sleep"
  sleep 0.01
  puts "wake up #{Time.now - t0}"
}

t0 = Time.now
t.join
puts "elapsed: #{Time.now - t0}"