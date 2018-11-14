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
  puts "disconnected: #{socket}"
rescue => e
  puts "*** error ***"
  puts e
  puts e.backtrace.join("\n")
end

server = Rubato::Net::Server.new
server.on(:connection) do |socket|
  Rubato.async { echo_connection(socket) }
end
server.listen(port: 1234)
puts "listening on port 1234"