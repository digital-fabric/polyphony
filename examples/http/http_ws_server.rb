# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/http'
require 'polyphony/websocket'

def ws_handler(conn)
  timer = spin do
    throttled_loop(1) do
      conn << Time.now.to_s
    end
  end
  while (msg = conn.recv)
    conn << "you said: #{msg}"
  end
ensure
  timer.stop
end

opts = {
  reuse_addr:  true,
  dont_linger: true,
  upgrade:     {
    websocket: Polyphony::Websocket.handler(&method(:ws_handler))
  }
}

HTML = IO.read(File.join(__dir__, 'ws_page.html'))

spin do
  Polyphony::HTTP::Server.serve('0.0.0.0', 1234, opts) do |req|
    req.respond(HTML, 'Content-Type' => 'text/html')
  end
end

puts "pid: #{Process.pid}"
puts 'Listening on port 1234...'
