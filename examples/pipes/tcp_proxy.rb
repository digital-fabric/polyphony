# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

DESTINATION = ['127.0.0.1', 1234]

def handle_client(conn)
  spin do
    dest = TCPSocket.new(*DESTINATION)
    # w_buffer = Polyphony.pipe
    # r_buffer = Polyphony.pipe
    
    # spin { IO.splice_to_eof(conn, w_buffer) }
    # spin { IO.splice_to_eof(w_buffer, dest) }

    # spin { IO.splice_to_eof(dest, r_buffer) }
    # spin { IO.splice_to_eof(r_buffer, conn) }

    # Fiber.current.await_all_children

    spin { IO.double_splice_to_eof(conn, dest) }
    IO.double_splice_to_eof(dest, conn)
  end
rescue SystemCallError
  dest.close rescue nil
  # ignore
end

puts "Serving TCP proxy on port 4321..."
TCPServer.new('127.0.0.1', 4321).accept_loop { |c| handle_client(c) }
