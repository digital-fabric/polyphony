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

    f = spin do
      IO.double_splice_to_eof(conn, dest)
      raise EOFError
    end
    IO.double_splice_to_eof(dest, conn)
    f.await
  rescue EOFError, SystemCallError
    # ignore
  ensure
    conn.close rescue nil
    dest.close rescue nil
  end
end

puts "Serving TCP proxy on port 4321..."
server = TCPServer.new('127.0.0.1', 4321)
while (conn = server.accept)
  handle_client(conn)
end
