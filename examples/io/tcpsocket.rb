# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'
require 'polyphony/extensions/backtrace'

socket = TCPSocket.new('google.com', 80)

timer = spin { throttled_loop(20) { STDOUT << '.' } }

5.times do
  socket.send("GET /?q=time HTTP/1.1\r\nHost: google.com\r\n\r\n", 0)
  socket.recv(8192)
  STDOUT << '*'
end

timer.stop
socket.close
puts
