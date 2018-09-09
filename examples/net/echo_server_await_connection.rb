require 'modulation'

Async       = import('../../lib/nuclear/core/async')
Net         = import('../../lib/nuclear/core/net')
LineReader  = import('../../lib/nuclear/core/line_reader')

def echo_connection(socket)
  puts "connected: #{socket}"
  Async.await socket.write("Echo server!\n")
  LineReader.new(socket).each_line do |line|
    break unless line
    Async.await socket.write("You said: #{line}")
  end
rescue => e
  puts "error: #{e}"
ensure
  puts "disconnected: #{socket}"
end

server = Net::Server.new
Async.run do
  while socket = Async.await(server.connection)
    Async.run { echo_connection(socket) }
  end
end

server.listen(port: 1234)
puts "listening on port 1234"
