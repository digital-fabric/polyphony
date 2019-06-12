# frozen_string_literal: true

require 'fiber'

ping = Fiber.new do |peer|
  loop do
    puts "ping"
    sleep 0.3
    peer.transfer Fiber.current
  end
end

pong = Fiber.new do |peer|
  loop do
    puts "pong"
    sleep 0.3
    peer.transfer Fiber.current
  end
end

ping.resume(pong)