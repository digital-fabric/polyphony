# frozen_string_literal: true

require 'modulation'

Rubato = import('../../lib/rubato')

def echo_connection(socket)
  puts "connected: #{socket}"
  Rubato.await socket.write("Echo server!\n")
  Rubato::LineReader.new(socket).each_line do |line|
    break unless line
    Rubato.await socket.write("You said: #{line}")
  end
rescue => e
  puts "error: #{e}"
ensure
  puts "disconnected: #{socket}"
end

server = Rubato::Net::Server.new
Rubato.async do
  while socket = Rubato.await(server.connection)
    Rubato.async { echo_connection(socket) }
  end
end

server.listen(port: 1234)
puts "listening on port 1234"
