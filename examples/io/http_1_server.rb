# frozen_string_literal: true

require 'modulation'
require 'http/parser'

Nuclear = import('../../lib/nuclear')

$client_count = 0

def handle_client(client)
  $client_count += 1
  parser = Http::Parser.new

  request_complete = false

  parser.on_message_complete = proc { request_complete = true }
  # parser.on_body = proc { |chunk| handle_body_chunk(ctx, chunk) }

  # move_on_after(10) do |scope|
    loop do
      data = await client.read
      # scope.reset_timeout
      parser << data
      if request_complete
        status_code = 200
        data = "Hello world!\n"
        headers = "Content-Length: #{data.bytesize}\r\n"
        await client.write "HTTP/1.1 #{status_code}\r\n#{headers}\r\n#{data}"
        request_complete = nil
        break unless parser.keep_alive?
      end
    end
    # puts "moved on due to inactivity"
  # end
rescue => e
  # puts "client error: #{e.inspect}"
ensure
  client.close
  $client_count -= 1
end

spawn do
  socket = ::Socket.new(:INET, :STREAM)
  server = Nuclear::IO::SocketWrapper.new(socket)
  await server.bind('127.0.0.1', 1234)
  await server.listen
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

# EV::Timer.new(60, 60) { GC.start }
EV::Timer.new(5, 5) do
  puts "%s %d clients: %d fibers: %d / %d" % [
    Time.now.to_s,
    Process.pid,
    $client_count,
    Nuclear::FiberPool.available,
    Nuclear::FiberPool.size
  ]
end
