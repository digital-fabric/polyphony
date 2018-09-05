#!/usr/bin/env ruby
# frozen_string_literal: true

require 'modulation'

Net =         import('../../lib/nuclear/net')
include       import('../../lib/nuclear/concurrency')

socket = Net::Socket.new
socket.connect('127.0.0.1', 1234, timeout: 3).
  then {
    socket.on(:data) do |data|
      STDOUT << data
    end
  
    Reactor.interval(1) { socket << "#{Time.now}\n" }
  }.
  catch { |err|
    puts "error: #{err}"
    exit
  }
