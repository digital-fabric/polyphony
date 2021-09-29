# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'
require 'http/parser'
require 'rack'

module RackAdapter
  class << self
    def run(app)
      ->(socket, req) { respond(socket, req, app.(env(req))) }
    end

    def env(req)
      {}
    end

    def respond(socket, request, (status_code, headers, body))
      body = body.join
      headers = "Content-Type: text/plain\r\nContent-Length: #{body.bytesize}\r\n"
      socket.write "HTTP/1.1 #{status_code}\r\n#{headers}\r\n#{body}"
    end
  end
end

$connection_count = 0

def handle_client(socket, &handler)
  $connection_count += 1
  parser = Http::Parser.new
  reqs = []
  parser.on_message_complete = proc do |env|
    reqs << Object.new # parser
  end
  socket.read_loop do |data|
    parser << data
    while (req = reqs.shift)
      handler.call(socket, req)
      req = nil
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

app = RackAdapter.run(lambda { |env|
  [
    200,
    {"Content-Type" => "text/plain"},
    ["Hello, world!\n"]
  ]
})

loop do
  client = server.accept
  spin { handle_client(client, &app) }
end
