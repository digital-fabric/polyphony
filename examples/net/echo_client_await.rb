#!/usr/bin/env ruby
# frozen_string_literal: true

require 'modulation'

Core  = import('../../lib/nuclear/core')
Net   = import('../../lib/nuclear/net')
include Core::Async

socket = Net::Socket.new

async do
  await socket.connect('127.0.0.1', 1234, timeout: 3)

  timer_id = Core::Reactor.interval(1) { socket << "#{Time.now}\n" }
  Core::Reactor.timeout(5) do
    Core::Reactor.cancel_timer(timer_id)
    socket.close
  end

  while data = await(socket.read) do
    STDOUT << data
  end
end
