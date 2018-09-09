require 'modulation'

Nuclear = import('../../lib/nuclear')

def echo_connection(socket)
  puts "connected: #{socket}"
  Nuclear.await socket.write("Echo server!\n")
  Nuclear::LineReader.new(socket).each_line do |line|
    break unless line
    Nuclear.await socket.write("You said: #{line}")
  end
rescue => e
  puts "error: #{e}"
ensure
  puts "disconnected: #{socket}"
end

server = Nuclear::Net::Server.new
Nuclear.async do
  while socket = Nuclear.await(server.connection)
    Nuclear.async { echo_connection(socket) }
  end
end

server.listen(port: 1234)
puts "listening on port 1234"
