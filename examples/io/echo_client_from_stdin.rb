# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

socket = Polyphony::Net.tcp_connect('127.0.0.1', 1234)

writer = spin do
  while (data = gets)
    socket << data
  end
end

reader = spin do
  socket.read_loop do |data|
    STDOUT << 'received: ' + data
  end
  writer.interrupt
end

suspend