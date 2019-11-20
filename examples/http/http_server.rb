# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/auto_run'
require 'polyphony/http'
require 'polyphony/extensions/backtrace'

opts = {
  reuse_addr: true,
  dont_linger: true
}

puts "Main fiber: #{Fiber.current.object_id}"

spin do
  Polyphony::HTTP::Server.serve('0.0.0.0', 1234, opts) do |req|
    req.respond("Hello world!\n")
  end
rescue Exception => e
  puts "*" * 40
  p e
  puts e.backtrace.join("\n")
end

puts "pid: #{Process.pid}"
puts "Listening on port 1234..."