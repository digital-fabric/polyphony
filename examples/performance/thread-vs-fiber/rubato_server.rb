# frozen_string_literal: true

require 'modulation'
require 'http/parser'

Rubato = import('../../../lib/rubato')

class Http::Parser
  def setup_async
    self.on_message_complete = proc { @request_complete = true }
  end

  def parse(data)
    self << data
    return nil unless @request_complete

    @request_complete = nil
    self
  end
end

async def handle_client(socket)
  parser = Http::Parser.new
  req = nil
  parser.on_message_complete = proc do |env|
    req = parser
  end
  loop do
    parser << socket.read
    if req
      handle_request(socket, req)
      req = nil
      EV.snooze
    end
  end
rescue IOError, SystemCallError => e
  # do nothing
ensure
  socket.close rescue nil
  parser.reset!
end

def handle_request(client, parser)
  status_code = 200
  data = "Hello world!\n"
  headers = "Content-Length: #{data.bytesize}\r\n"
  client.write "HTTP/1.1 #{status_code}\r\n#{headers}\r\n#{data}"
end

spawn do
  server = TCPServer.open(1234)
  puts "listening on port 1234"

  loop do
    client = server.accept
    spawn handle_client(client)
  end
rescue Exception => e
  puts "uncaught exception: #{e.inspect}"
  puts e.backtrace.join("\n")
  exit!
  server.close
end
