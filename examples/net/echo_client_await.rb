# frozen_string_literal: true

require 'modulation'

Rubato = import('../../lib/rubato')

socket = Rubato::Net::Socket.new

Rubato.async do
  Rubato.await socket.connect('127.0.0.1', 1234, timeout: 3)

  timer = Rubato.interval(1) { socket << "#{Time.now}\n" }
  Rubato.timeout(5) do
    timer.stop
    socket.close
  end

  while data = Rubato.await(socket.read) do
    STDOUT << data
  end
end
