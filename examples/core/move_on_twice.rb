# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

puts "going to sleep..."
move_on_after(1) do
  sleep 60
end
puts "woke up"

puts "going to sleep..."
move_on_after(1) do
  sleep 60
end
puts "woke up"
