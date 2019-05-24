# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

socket = Polyphony::Net.tcp_connect('127.0.0.1', 1234)

writer = coproc do
  throttled_loop(1) { socket << "#{Time.now}\n" rescue nil }
end

reader = coproc do
  puts "received from echo server:"
  while data = socket.readpartial(8192)
    STDOUT << data
  end
end

sleep(5)
[reader, writer].each(&:stop)
socket.close
