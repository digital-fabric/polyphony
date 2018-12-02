require 'thread'
require 'http/parser'
require 'socket'

def handle_client(client)
  Thread.new do
    parser = Http::Parser.new
    parser.on_message_complete= proc do |env|
      status_code = 200
      data = "Hello world!\n"
      headers = "Content-Length: #{data.bytesize}\r\n"
      client.write "HTTP/1.1 #{status_code}\r\n#{headers}\r\n#{data}"
    end
    loop do
      while data = client.readpartial(8192) rescue nil
        parser << data
      end
    end
    client.close
  end
end

server = TCPServer.open(1234)
puts "Listening on port 1234"
while socket = server.accept
  handle_client(socket)
end