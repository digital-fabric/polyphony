# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

next_tick do
  puts "two"
  next_tick { puts "four" }
  puts "three"
end

puts "one"