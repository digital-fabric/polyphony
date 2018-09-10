# frozen_string_literal: true

require 'modulation'

Nuclear = import('../../lib/nuclear')

socket = Nuclear::Net::Socket.new
socket.connect('127.0.0.1', 1234, timeout: 3).
  then {
    socket.on(:data) do |data|
      STDOUT << data
    end
  
    timer_id = Nuclear.interval(1) { socket << "#{Time.now}\n" }
    Nuclear.timeout(5) do
      Nuclear.cancel_timer(timer_id)
      socket.close
    end
  }.
  catch { |err|
    puts "error: #{err}"
    exit
  }
