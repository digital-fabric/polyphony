# frozen_string_literal: true

require 'modulation'
require 'http/parser'

Nuclear = import('../../lib/nuclear')

$client_count = 0
$request_count = 0

def handle_client(client)
  client.set_no_delay
  $client_count += 1
  conn_request_count = 0
  # puts "> count: #{$client_count}"
  parser = Http::Parser.new

  request_complete = false

  parser.on_message_complete = proc { request_complete = true }
  # parser.on_body = proc { |chunk| handle_body_chunk(ctx, chunk) }

  move_on_after(60) do |scope|
    scope.on_cancel { puts "moving on..."; client.dont_linger }
    loop do
      data = await client.read
      scope.reset_timeout
      parser << data
      if request_complete
        conn_request_count += 1
        $request_count += 1
        status_code = 200
        data = "Hello world!\n"
        headers = "Content-Length: #{data.bytesize}\r\n"
        await client.write "HTTP/1.1 #{status_code}\r\n#{headers}\r\n#{data}"
        request_complete = nil
        parser.keep_alive? ? resume_on_next_tick : break
      end
    end
  end
rescue Errno::ECONNRESET, IOError => e
  # ignore
rescue => e
  puts "client error: #{e.inspect}"
ensure
  client.close
  $client_count -= 1
  # puts "< count: #{$client_count} (#{conn_request_count})"
end

spawn do
  socket = ::Socket.new(:INET, :STREAM)
  server = Nuclear::IO::SocketWrapper.new(socket)
  server.reuse_addr
  server.dont_linger
  await server.bind('0.0.0.0', 1234)
  await server.listen
  server.dont_linger
  puts "listening on port 1234..."

  loop do
    client = await server.accept
    # puts "accept #{client.inspect}"
    spawn { handle_client(client) }
  end
rescue Exception => e
  puts "uncaught exception: #{e.inspect}"
  server.close
end

t0 = Time.now
last_t = Time.now
last_request_count = 0
Nuclear.every(5) do
  now = Time.now
  if now > last_t
    rate = ($request_count - last_request_count) / (now - last_t)
    last_request_count = $request_count
    last_t = now
  else
    rate = 0
  end

  puts "pid: %d uptime: %d clients: %d req/s: %d fibers: %d - %d / %d" % [
    Process.pid,
    (Time.now - t0).to_i,
    $client_count,
    rate,
    Nuclear::FiberPool.available,
    Nuclear::FiberPool.checked_out,
    Nuclear::FiberPool.size
  ]
end

Nuclear.every(1) do
  GC.start
end