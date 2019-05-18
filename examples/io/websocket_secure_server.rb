# frozen_string_literal: true

require 'modulation'
require 'localhost/authority'

STDOUT.sync = true

Polyphony = import('../../lib/polyphony')
HTTPServer = import('../../lib/polyphony/http/server')
Websocket = import('../../lib/polyphony/websocket')

def ws_handler(conn)
  while msg = conn.recv
    conn << "you said: #{msg}"
  end
end

authority = Localhost::Authority.fetch
opts = {
  reuse_addr: true,
  dont_linger: true,
  upgrade: {
    websocket: Websocket.handler(&method(:ws_handler))
  },
  secure_context: authority.server_context
}

server = HTTPServer.serve('0.0.0.0', 1234, opts) do |req|
  req.respond("Hello world!\n")
end

puts "pid: #{Process.pid}"
puts "Listening on port 1234..."
server.await
puts "bye bye"

