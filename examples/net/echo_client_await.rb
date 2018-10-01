# frozen_string_literal: true

require 'modulation'

Nuclear = import('../../lib/nuclear')

socket = Nuclear::Net::Socket.new

Nuclear.async do
  Nuclear.await socket.connect('127.0.0.1', 1234, timeout: 3)

  timer = Nuclear.interval(1) { socket << "#{Time.now}\n" }
  Nuclear.timeout(5) do
    timer.stop
    socket.close
  end

  while data = Nuclear.await(socket.read) do
    STDOUT << data
  end
end
