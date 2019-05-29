# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

socket = TCPSocket.new('realiteq.net', 80)

socket.send("GET /?q=time HTTP/1.1\r\nHost: realiteq.net\r\n\r\n", 0)
puts socket.recv(8192)

socket.close