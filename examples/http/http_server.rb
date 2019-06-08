# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/http'

opts = { reuse_addr: true, dont_linger: true }
spin {
  Polyphony::HTTP::Server.serve('0.0.0.0', 1234, opts) do |req|
    req.respond("Hello world!\n")
  end
}

puts "pid: #{Process.pid}"
puts "Listening on port 1234..."