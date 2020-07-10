# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

X = 1_000_000

GC.disable

count = 0

pong = spin_loop do
  msg, ping = receive
  count += 1
  ping << 'pong'
end

ping = spin do
  X.times do
    pong << ['ping', Fiber.current]
    msg = receive
    count += 1
  end
end

t0 = Time.now
ping.await
dt = Time.now - t0
puts format('message rate: %d/s', (X / dt))
