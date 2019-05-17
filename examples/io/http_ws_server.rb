# frozen_string_literal: true

require 'modulation'

STDOUT.sync = true

Polyphony = import('../../lib/polyphony')
HTTPServer = import('../../lib/polyphony/http/server')
Websocket = import('../../lib/polyphony/websocket')

def ws_handler(conn)
  timer = spawn {
    throttled_loop(1) {
      conn << Time.now.to_s
    }
  }
  while msg = conn.recv
    # conn << "you said: #{msg}"
  end
ensure
  timer.stop
end

opts = {
  reuse_addr: true,
  dont_linger: true,
  upgrade: {
    websocket: Websocket.handler(&method(:ws_handler))
  }
}

HTML = IO.read(File.join(__dir__, 'ws_page.html'))

server = HTTPServer.serve('0.0.0.0', 1234, opts) do |req|
  req.respond(HTML, 'Content-Type' => 'text/html')
end

puts "pid: #{Process.pid}"
puts "Listening on port 1234..."
server.await
puts "bye bye"

