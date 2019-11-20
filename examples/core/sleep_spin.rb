# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

spin do
  10.times do |i|
    sleep 0.1
    p i
  end
end

spin do
  puts 'going to sleep...'
  sleep 1
  puts 'woke up'
end.await

puts 'done'
