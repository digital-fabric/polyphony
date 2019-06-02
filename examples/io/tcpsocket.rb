# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

socket = TCPSocket.new('realiteq.net', 80)

timer = coproc { throttled_loop(20) { STDOUT << '.' } }

5.times do
  socket.send("GET /?q=time HTTP/1.1\r\nHost: realiteq.net\r\n\r\n", 0)
  socket.recv(8192)
  STDOUT << "*"
end

timer.stop
socket.close
puts