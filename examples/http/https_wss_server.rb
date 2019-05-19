# frozen_string_literal: true

require 'modulation'
require 'localhost/authority'

STDOUT.sync = true

Polyphony = import('../../lib/polyphony')
HTTPServer = import('../../lib/polyphony/http/server')
Websocket = import('../../lib/polyphony/websocket')

def ws_handler(conn)
  timer = spawn {
    throttled_loop(1) {
      conn << Time.now.to_s rescue nil
    }
  }
  while msg = conn.recv
    puts "msg: #{msg}"
    # conn << "you said: #{msg}"
  end
ensure
  timer.stop
end

authority = Localhost::Authority.fetch
opts = {
  reuse_addr: true,
  dont_linger: true,
  secure_context: authority.server_context,
  upgrade: {
    websocket: Websocket.handler(&method(:ws_handler))
  }
}

HTML = IO.read(File.join(__dir__, 'wss_page.html'))

server = HTTPServer.serve('0.0.0.0', 1234, opts) do |req|
  req.respond(HTML, 'Content-Type' => 'text/html')
end

puts "pid: #{Process.pid}"
puts "Listening on port 1234..."
server.await
puts "bye bye"

