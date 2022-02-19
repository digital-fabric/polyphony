# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

require 'polyphony/core/debug'
Polyphony::Trace.start_event_firehose(STDOUT)

pong = spin_loop(:pong) do
  msg, ping = receive
  puts msg
  ping << 'pong'
end

ping = spin(:ping) do
  1.times do
    pong << ['ping', Fiber.current]
    msg = receive
    puts msg
  end
end

ping.await
