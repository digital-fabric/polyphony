# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

DESTINATION = ['127.0.0.1', 1234]

def handle_client(conn)
  spin do
    dest = TCPSocket.new(*DESTINATION)
    # w_buffer = Polyphony.pipe
    # r_buffer = Polyphony.pipe

    # spin { IO.splice(conn, w_buffer, -1000) }
    # spin { IO.splice(w_buffer, dest, -1000) }

    # spin { IO.splice(dest, r_buffer, -1000) }
    # spin { IO.splice(r_buffer, conn, -1000) }

    # Fiber.current.await_all_children

    f = spin do
      IO.double_splice(conn, dest)
      raise EOFError
    end
    IO.double_splice(dest, conn)
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
