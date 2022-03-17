# frozen_string_literal: true

require 'bundler/setup'

require 'polyphony'
require 'h1p'

server = Polyphony::Net.tcp_listen('localhost', 1234,
  reuse_addr: true, reuse_port: true, dont_linger: true
)
puts 'Serving HTTP on port 1234'

def respond_default(conn)
  conn << "HTTP/1.1 204\r\n\r\n"
end

def respond_splice(conn, path)
  f = File.open(path, 'r') do |f|
    conn << "HTTP/1.1 200\r\nTransfer-Encoding: chunked\r\n\r\n"
    IO.http1_splice_chunked(f, conn, 16384)
  end
rescue => e
  p e
  # conn << "HTTP/1.1 500\r\nContent-Length: 0\r\n\r\n"
end

def handle_client(conn)
  parser = H1P::Parser.new(conn, :server)
  while true
    headers = parser.parse_headers
    break unless headers

    case headers[':path']
    when /^\/splice\/(.+)$/
      respond_splice(conn, $1)
    else
      respond_default(conn)
    end
  end
rescue Errno::ECONNRESET
  # ignore
end

server.accept_loop do |conn|
  handle_client(conn)
end
