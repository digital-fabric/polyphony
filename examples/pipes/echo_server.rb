# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

def handle_client(conn)
  spin do
    IO.double_splice_to_eof(conn, conn)
    # buffer = Polyphony.pipe
    # spin { IO.splice_to_eof(conn, buffer) }
    # IO.splice_to_eof(buffer, conn)
  rescue SystemCallError
    # ignore
  ensure
    conn.close rescue nil
  end
end

puts "Serving echo on port 1234..."
TCPServer.new('127.0.0.1', 1234).accept_loop { |c| handle_client(c) }
