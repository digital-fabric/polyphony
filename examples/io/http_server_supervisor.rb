# frozen_string_literal: true

require 'modulation'
require 'http/parser'

Rubato = import('../../lib/rubato')

$client_count = 0
$request_count = 0

async def socket_reader(supervisor, socket, responder_fiber)
  parser = Http::Parser.new
  parser.on_message_complete = proc { EV.next_tick { responder_fiber.resume(parser) } }
  loop do
    parser << await(socket.read)
  end
rescue IOError, SystemCallError => e
  supervisor.stop!
end

async def http_responder(supervisor, socket)
  loop do
    request = suspend
    if request == :stop
      supervisor.stop!
      return
    end
    handle_request(socket, request)
    break unless request.keep_alive?
  end
rescue IOError, SystemCallError => e
  # do nothing
ensure
  supervisor.stop!
end

async def supervise_client(socket)
  $client_count += 1
  await supervise do |supervisor|
    responder = supervisor.spawn http_responder(supervisor, socket)
    supervisor.spawn socket_reader(supervisor, socket, responder.fiber)
  end  
ensure
  $client_count -= 1
  socket.close rescue nil
end

def handle_request(client, parser)
  $request_count += 1
  status_code = 200
  data = "Hello world!\n"
  headers = "Content-Length: #{data.bytesize}\r\n"
  await client.write "HTTP/1.1 #{status_code}\r\n#{headers}\r\n#{data}"
end

spawn do
  server = await Rubato::Net.tcp_listen(nil, 1234, reuse_addr: true, dont_linger: true)
  puts "listening on port 1234..."

  loop do
    client = await server.accept
    spawn supervise_client(client)
  end
rescue Exception => e
  puts "uncaught exception: #{e.inspect}"
  puts e.backtrace.join("\n")
  exit!
  server.close
end

t0 = Time.now
last_t = Time.now
last_request_count = 0

every(5) do
  now = Time.now
  if now > last_t
    rate = ($request_count - last_request_count) / (now - last_t)
    last_request_count = $request_count
    last_t = now
  else
    rate = 0
  end

  puts "pid: %d uptime: %d clients: %d req/s: %d" % [
    Process.pid,
    (Time.now - t0).to_i,
    $client_count,
    rate
  ]
end

# Rubato.every(1) do
#   GC.start
# end