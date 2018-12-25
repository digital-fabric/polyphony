# frozen_string_literal: true

require 'modulation'
require 'localhost/authority'

Rubato = import('../../lib/rubato')
HTTPServer = import('../../lib/rubato/http/server')

spawn do
  authority = Localhost::Authority.fetch
  opts = {
    reuse_addr: true,
    dont_linger: true,
    secure_context: authority.server_context
  }
  server = HTTPServer.serve('0.0.0.0', 1234, opts) do |req|
    req.respond("Hello world!\n")
  end
  server.await
end

puts "pid: #{Process.pid}"
puts "Listening on port 1234..."