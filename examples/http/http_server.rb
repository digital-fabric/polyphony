# frozen_string_literal: true

require 'modulation'

Polyphony = import('../../lib/polyphony')

opts = { reuse_addr: true, dont_linger: true }
spawn {
  Polyphony::HTTP::Server.serve('0.0.0.0', 1234, opts) do |req|
    req.respond("Hello world!\n")
  end
}

puts "pid: #{Process.pid}"
puts "Listening on port 1234..."