# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

socket = Polyphony::Net.tcp_connect('127.0.0.1', 1234)

writer = spin do
  throttled_loop(1) do
    socket << "#{Time.now}\n"
  rescue StandardError
    nil
  end
end

reader = spin do
  puts 'received from echo server:'
  while (data = socket.readpartial(8192))
    STDOUT << data
  end
end

sleep(5)
[reader, writer].each(&:stop)
socket.close
