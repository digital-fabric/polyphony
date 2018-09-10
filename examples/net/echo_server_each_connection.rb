# frozen_string_literal: true

require 'modulation'

Nuclear = import('../../lib/nuclear')

def echo_connection(socket)
  Nuclear.await socket.write("Echo server!\n")
  Nuclear::LineReader.new(socket).each_line do |line|
    break unless line
    Nuclear.await socket.write("You said: #{line}")
  end
end

server = Nuclear::Net::Server.new
Nuclear.async do
  server.each_connection do |socket|
    Nuclear.async { echo_connection(socket) }
  end
end

server.listen(port: 1234)
puts "listening on port 1234"

puts "pid: #{Process.pid}"