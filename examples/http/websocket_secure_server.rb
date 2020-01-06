# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/http'
require 'localhost/authority'

def ws_handler(conn)
  while (msg = conn.recv)
    conn << "you said: #{msg}"
  end
end

authority = Localhost::Authority.fetch
opts = {
  reuse_addr:     true,
  dont_linger:    true,
  upgrade:        {
    websocket: Polyphony::Websocket.handler(&method(:ws_handler))
  },
  secure_context: authority.server_context
}

puts "pid: #{Process.pid}"
puts 'Listening on port 1234...'
Polyphony::HTTP::Server.serve('0.0.0.0', 1234, opts) do |req|
  req.respond("Hello world!\n")
end
