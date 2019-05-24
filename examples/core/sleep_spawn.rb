# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

coproc {
  10.times { |i|
    sleep 0.1;
    p i
  }
}

coproc {
  puts "going to sleep..."
  sleep 1
  puts "woke up"
}.await

puts "done"