# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'
require 'http/parser'

def handle_client(socket)
  pending_requests = []
  parser = Http::Parser.new
  parser.on_message_complete = proc { pending_requests << parser }

  socket.recv_loop do |data|
    parser << data
    write_response(socket) while pending_requests.shift
  end
rescue IOError, SystemCallError => e
  # do nothing
ensure
  socket&.close
end

def write_response(socket)
  status_code = "200 OK"
  data = "Hello world!\n"
  headers = "Content-Type: text/plain\r\nContent-Length: #{data.bytesize}\r\n"
  socket.write "HTTP/1.1 #{status_code}\r\n#{headers}\r\n#{data}"
end

server = TCPServer.open('0.0.0.0', 4411)
puts "pid #{Process.pid} Polyphony (#{Thread.current.backend.kind}) listening on port 4411"

spin_loop(interval: 10) do
  p Thread.current.fiber_scheduling_stats
end

server.accept_loop do |c|
  spin { handle_client(c) }
end
