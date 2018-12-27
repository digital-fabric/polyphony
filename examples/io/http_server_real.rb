# frozen_string_literal: true

require 'modulation'
require 'http/parser'

Rubato = import('../../lib/rubato')
HTTPServer = import('../../lib/rubato/http/server')

opts = { reuse_addr: true, dont_linger: true }
server = HTTPServer.serve('0.0.0.0', 1234, opts) do |req|
  req.respond("Hello world!\n")
end
puts "pid: #{Process.pid}"
puts "root fiber: #{Fiber.current}"
puts "Listening on port 1234..."
server.await
puts "bye bye"

