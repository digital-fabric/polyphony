# frozen_string_literal: true

require 'modulation'

STDOUT.sync = true

Polyphony = import('../../lib/polyphony')

def ws_handler(conn)
  while msg = conn.recv
    conn << "you said: #{msg}"
  end
end

opts = {
  reuse_addr: true,
  dont_linger: true,
  upgrade: {
    websocket: Polyphony::Websocket.handler(&method(:ws_handler))
  }
}

puts "pid: #{Process.pid}"
puts "Listening on port 1234..."
Polyphony::HTTP::Server.serve('0.0.0.0', 1234, opts) do |req|
  req.respond("Hello world!\n")
end