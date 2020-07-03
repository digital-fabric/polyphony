# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'
require 'http/parser'

$connection_count = 0

def handle_client(socket)
  $connection_count += 1
  parser = Http::Parser.new
  reqs = []
  parser.on_message_complete = proc do |env|
    reqs << Object.new # parser
  end
  while (data = socket.readpartial(8192)) do
    parser << data
    while (req = reqs.shift)
      handle_request(socket, req)
      req = nil
      snooze
    end
  end
rescue IOError, SystemCallError => e
  # do nothing
ensure
  $connection_count -= 1
  socket&.close
end

def handle_request(client, parser)
  status_code = "200 OK"
  data = "Hello world!\n"
  headers = "Content-Type: text/plain\r\nContent-Length: #{data.bytesize}\r\n"
  client.write "HTTP/1.1 #{status_code}\r\n#{headers}\r\n#{data}"
end

server = TCPServer.open('0.0.0.0', 1234)
puts "pid #{Process.pid}"
puts "listening on port 1234"

loop do
  client = server.accept
  spin { handle_client(client) }
end
