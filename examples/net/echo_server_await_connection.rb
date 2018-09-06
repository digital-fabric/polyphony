#!/usr/bin/env ruby
# frozen_string_literal: true

require 'modulation'

Core        = import('../../lib/nuclear/core')
Net         = import('../../lib/nuclear/net')
LineReader  = import('../../lib/nuclear/line_reader')
include Core::Async

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
async do
  while socket = await(server.connection)
    async { echo_connection(socket) }
  end
end

server.listen(port: 1234)
puts "listening on port 1234"

puts "pid: #{Process.pid}"