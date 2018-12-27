# frozen_string_literal: true

require 'modulation'

Rubato = import('../../lib/rubato')

socket = Rubato::Net.tcp_connect('127.0.0.1', 1234)

writer = spawn do
  throttled_loop(1) { socket << "#{Time.now}\n" }
end

reader = spawn do
  puts "received from echo server:"
  while data = socket.read
    STDOUT << data
  end
end

sleep(5)
[reader, writer].each(&:stop)
socket.close
