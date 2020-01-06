# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

spin do
  puts '1 >'
  sleep(1)
  puts '1 <'
end

spin do
  puts '2 >'
  sleep(1)
  puts '2 <'
end

suspend