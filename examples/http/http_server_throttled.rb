# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/http'

$throttler = throttle(1000)
opts = { reuse_addr: true, dont_linger: true }
spin do
  Polyphony::HTTP::Server.serve('0.0.0.0', 1234, opts) do |req|
    $throttler.call { req.respond("Hello world!\n") }
  end
end

puts "pid: #{Process.pid}"
puts 'Listening on port 1234...'
