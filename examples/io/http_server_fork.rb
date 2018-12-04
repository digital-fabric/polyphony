# frozen_string_literal: true

require 'modulation'
require 'http/parser'

Rubato = import('../../lib/rubato')

$client_count = 0
$request_count = 0

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
  $client_count += 1
  parser = Http::Parser.new
  parser.setup_async
  loop do
    data = socket.read
    if request = parser.parse(data)
      handle_request(socket, nil)
      request.keep_alive? ? EV.snooze : break
    end
  end
rescue IOError, SystemCallError => e
  # do nothing
ensure
  $client_count -= 1
  socket.close rescue nil
  parser.reset!
end

def handle_request(client, parser)
  $request_count += 1
  status_code = 200
  data = "Hello world!\n"
  headers = "Content-Length: #{data.bytesize}\r\n"
  client.write "HTTP/1.1 #{status_code}\r\n#{headers}\r\n#{data}"
end

server = Rubato::Net.tcp_listen(nil, 1234,
  reuse_addr: true, dont_linger: true
)
puts "listening on port 1234..."

child_pids = []
4.times do
  child_pids << Rubato.fork do
    puts "forked pid: #{Process.pid}"
    spawn do
      loop do
        client = server.accept
        spawn handle_client(client)
      end
    end
  end
end

spawn do
  child_pids.each { |pid| EV::Child.new(pid).await }
end