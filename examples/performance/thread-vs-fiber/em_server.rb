require 'eventmachine'
require 'http/parser'
require 'socket'

module HTTPServer
  def post_init
    @parser = Http::Parser.new
    @pending_requests = []
    @parser.on_message_complete = proc { @pending_requests << @parser }
  end

  def receive_data(data)
    @parser << data
    write_response while @pending_requests.shift
  end

  def write_response
    status_code = "200 OK"
    data = "Hello world!\n"
    headers = "Content-Type: text/plain\r\nContent-Length: #{data.bytesize}\r\n"
    send_data "HTTP/1.1 #{status_code}\r\n#{headers}\r\n#{data}"
  end
end

EventMachine::run do
  EventMachine::start_server(
    '0.0.0.0',
    1236,
    HTTPServer
  )
  puts "pid #{Process.pid} EventMachine listening on port 1236"

end
