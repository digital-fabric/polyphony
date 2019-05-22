# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

spawn {
  10.times { |i|
    sleep 0.1;
    p i
  }
}

spawn {
  puts "going to sleep..."
  sleep 1
  puts "woke up"
}.await

puts "done"