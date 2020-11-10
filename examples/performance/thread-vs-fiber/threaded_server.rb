require 'http/parser'
require 'socket'

def handle_client(socket)
  pending_requests = []
  parser = Http::Parser.new
  parser.on_message_complete = proc { pending_requests << parser }

  while (data = socket.recv(8192))
    parser << data
    write_response(socket) while pending_requests.shift
  end
rescue IOError, SystemCallError => e
  # ignore
ensure
  socket.close
end

def write_response(socket)
  status_code = "200 OK"
  data = "Hello world!\n"
  headers = "Content-Type: text/plain\r\nContent-Length: #{data.bytesize}\r\n"
  socket.write "HTTP/1.1 #{status_code}\r\n#{headers}\r\n#{data}"
end

server = TCPServer.open(1235)
puts "pid #{Process.pid} threaded listening on port 1235"
while socket = server.accept
  Thread.new { handle_client(socket) }
end