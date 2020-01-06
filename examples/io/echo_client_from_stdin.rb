# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'
require 'polyphony/extensions/backtrace'

socket = Polyphony::Net.tcp_connect('127.0.0.1', 1234)

writer = spin do
  while (data = gets)
    socket << data
  end
end

spin do
  while (data = socket.readpartial(8192))
    STDOUT << 'received: ' + data
  end
  writer.interrupt
end

suspend