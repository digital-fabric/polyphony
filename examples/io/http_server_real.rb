# frozen_string_literal: true

require 'modulation'
require 'http/parser'

Rubato = import('../../lib/rubato')
HTTPServer = import('../../lib/rubato/http/server')

spawn do
  opts = { reuse_addr: true, dont_linger: true }
  server = HTTPServer.serve('0.0.0.0', 1234, opts) do |req|
    req.respond("Hello world!\n")
  end
  server.await
end

puts "pid: #{Process.pid}"
puts "Listening on port 1234..."