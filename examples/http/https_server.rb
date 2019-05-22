# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/http'
require 'localhost/authority'

authority = Localhost::Authority.fetch
opts = {
  reuse_addr: true,
  dont_linger: true,
  secure_context: authority.server_context
}

puts "pid: #{Process.pid}"
puts "Listening on port 1234..."
Polyphony::HTTP::Server.serve('0.0.0.0', 1234, opts) do |req|
  req.respond("Hello world!\n")
end