# frozen_string_literal: true

require 'modulation'

Rubato = import('../../lib/rubato')
HTTPServer = import('../../lib/rubato/http/server')

$throttler = throttle(1000)
opts = { reuse_addr: true, dont_linger: true }
server = HTTPServer.serve('0.0.0.0', 1234, opts) do |req|
  $throttler.call { req.respond("Hello world!\n") }
end
puts "pid: #{Process.pid}"
puts "Listening on port 1234..."
server.await
puts "bye bye"
