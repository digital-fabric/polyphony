# frozen_string_literal: true

require 'modulation'

Rubato = import('../../lib/rubato')

def echo_connection(socket)
  Rubato.await socket.write("Echo server!\n")
  Rubato::LineReader.new(socket).each_line do |line|
    break unless line
    Rubato.await socket.write("You said: #{line}")
  end
end

server = Rubato::Net::Server.new
Rubato.async do
  server.each_connection do |socket|
    Rubato.async { echo_connection(socket) }
  end
end

server.listen(port: 1234)
puts "listening on port 1234"

puts "pid: #{Process.pid}"