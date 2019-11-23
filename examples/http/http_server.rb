# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/auto_run'
require 'polyphony/http'
require 'polyphony/extensions/backtrace'

opts = {
  reuse_addr:  true,
  dont_linger: true
}

spin do
  Polyphony::HTTP::Server.serve('0.0.0.0', 1234, opts) do |req|
    req.respond("Hello world!\n")
  end
end

spin do
  throttled_loop(1) do
    Polyphony::FiberPool.compact
    puts "Fiber count: #{Polyphony::FiberPool.stats[:total]}"
  end
end

puts "pid: #{Process.pid}"
puts 'Listening on port 1234...'
