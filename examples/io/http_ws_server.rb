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
    puts "recv #{msg}"
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

HTML = <<~EOF
<!doctype html>
<html lang="en">
<head>
  <title>Websocket Client</title>
</head>
<body>
  <script>
    var exampleSocket = new WebSocket("ws://localhost:1234");
    exampleSocket.onopen = function (event) {
      document.querySelector('#status').innerText = 'connected';
      exampleSocket.send("Can you hear me?"); 
    };
    exampleSocket.onmessage = function (event) {
      document.querySelector('#msg').innerText = event.data;
      console.log(event.data);
    }
  </script>
  <h1 id="status"></h1>
  <h1 id="msg"></h1>
</body>
</html>
EOF

server = HTTPServer.serve('0.0.0.0', 1234, opts) do |req|
  req.respond(HTML, 'Content-Type' => 'text/html')
end

puts "pid: #{Process.pid}"
puts "Listening on port 1234..."
server.await
puts "bye bye"

