# frozen_string_literal: true

require 'modulation'
require 'http/parser'
require 'localhost/authority'

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
      EV.snooze
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

spawn do
  authority = Localhost::Authority.fetch
  server = Rubato::Net.tcp_listen(nil, 1234,
    reuse_addr: true, dont_linger: true,
    secure_context: authority.server_context
  )
  puts "listening (HTTPS) on port 1234..."

  loop do
    client = server.accept
    spawn handle_client(client)
  rescue => e
    puts "error in accept: #{e}"
  end
rescue Exception => e
  puts "uncaught exception: #{e.inspect}"
  puts e.backtrace.join("\n")
  exit!
  server.close
end

# t0 = Time.now
# last_t = Time.now
# last_request_count = 0

# puts "pid: #{Process.pid}"

# every(5) do
#   now = Time.now
#   if now > last_t
#     rate = ($request_count - last_request_count) / (now - last_t)
#     last_request_count = $request_count
#     last_t = now
#   else
#     rate = 0
#   end

#   puts "pid: %d uptime: %d clients: %d req/s: %d" % [
#     Process.pid,
#     (Time.now - t0).to_i,
#     $client_count,
#     rate
#   ]
# end
