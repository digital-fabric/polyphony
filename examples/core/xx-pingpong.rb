# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

pong = spin_loop do
  msg, ping = receive
  puts msg
  ping << 'pong'
end

ping = spin_loop do
  pong << ['ping', Fiber.current]
  msg = receive
  puts msg
end

suspend