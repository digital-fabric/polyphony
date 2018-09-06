#!/usr/bin/env ruby
# frozen_string_literal: true

require 'modulation'

Core  = import('../../lib/nuclear/core')
Net   = import('../../lib/nuclear/net')

socket = Net::Socket.new
socket.connect('127.0.0.1', 1234, timeout: 3).
  then {
    socket.on(:data) do |data|
      STDOUT << data
    end
  
    timer_id = Core::Reactor.interval(1) { socket << "#{Time.now}\n" }
    Core::Reactor.timeout(5) do
      Core::Reactor.cancel_timer(timer_id)
      socket.close
    end
  }.
  catch { |err|
    puts "error: #{err}"
    exit
  }
