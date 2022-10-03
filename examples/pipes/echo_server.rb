# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

def handle_client(conn)
  spin do
    IO.double_splice(conn, conn)
    # buffer = Polyphony.pipe
    # spin { IO.splice(conn, buffer, -1000) }
    # IO.splice(buffer, conn, -1000)
  rescue SystemCallError
    # ignore
  ensure
    conn.close rescue nil
  end
end

puts "Serving echo on port 1234..."
TCPServer.new('0.0.0.0', 1234).accept_loop { |c| handle_client(c) }
