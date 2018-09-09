#!/usr/bin/env ruby
# frozen_string_literal: true

require 'modulation'

Async       = import('../../lib/nuclear/core/async')
Net         = import('../../lib/nuclear/core/net')
LineReader  = import('../../lib/nuclear/core/line_reader')
include Async

def echo_connection(socket)
  puts "connected: #{socket}"
  await socket.write("Echo server!\n")
  LineReader.new(socket).each_line do |line|
    break unless line
    await socket.write("You said: #{line}")
  end
  puts "disconnected: #{socket}"
rescue => e
  puts "*** error ***"
  puts e
  puts e.backtrace.join("\n")
end

server = Net::Server.new
server.on(:connection) do |socket|
  async { echo_connection(socket) }
end
server.listen(port: 1234)
puts "listening on port 1234"