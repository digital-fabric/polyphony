# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

require 'polyphony'

def handle_echo_client(conn)
  buffer = Polyphony.pipe
  spin { buffer.splice_to_eof_from(conn) }
  spin { conn.splice_to_eof_from(buffer) }
end

puts "Serving echo on port 1234..."
TCPServer.new('127.0.0.1', 1234).accept_loop { |c| handle_echo_client(c) }
