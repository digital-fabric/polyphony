# frozen_string_literal: true

require 'bundler'
require 'modulation'

Polyphony = import('../../lib/polyphony')

# HTTPServer = import('polyphony/http/server')
p Polyphony::HTTP
p Polyphony::HTTP::Server
exit

p 1
opts = { reuse_addr: true, dont_linger: true }
server = Polyphony::HTTP::Server.serve('0.0.0.0', 1234, opts) do |req|
  req.respond("Hello world!\n")
end
p 2
puts "pid: #{Process.pid}"
puts "Listening on port 1234..."
server.await
puts "bye bye"

