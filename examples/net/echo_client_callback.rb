# frozen_string_literal: true

require 'modulation'

Rubato = import('../../lib/rubato')

socket = Rubato::Net::Socket.new
socket.connect('127.0.0.1', 1234, timeout: 3).
  then {
    socket.on(:data) do |data|
      STDOUT << data
    end
  
    timer = Rubato.interval(1) { socket << "#{Time.now}\n" }
    Rubato.timeout(5) do
      timer.stop
      socket.close
    end
  }.
  catch { |err|
    puts "error: #{err}"
    exit
  }
