# frozen_string_literal: true

require 'bundler/inline'

gemfile do
  gem 'h1p'
  gem 'polyphony', path: '.'
end

require 'polyphony'
require 'h1p'

def handle_client(conn)
  spin do
    parser = H1P::Parser.new(conn, :server)
    
    while true # assuming persistent connection
      headers = parser.parse_headers
      break unless headers

      raw_buffer = Polyphony.pipe
      gzip_buffer = Polyphony.pipe
      
      # splice request body to buffer
      spin do
        parser.splice_body_to(raw_buffer)
        raw_buffer.close
      end

      # zip data from buffer into gzip buffer
      spin do
        IO.gzip(raw_buffer, gzip_buffer)
        gzip_buffer.close
      end

      # send headers and splice response from gzip buffer
      conn << "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n"
      IO.http1_splice_chunked(gzip_buffer, conn, 65535)
    end
  rescue H1P::Error
    puts 'Got invalid request, closing connection...'
  ensure
    conn.close
  end
end

puts "Serving echo on port 1234..."
TCPServer.new('127.0.0.1', 1234).accept_loop { |c| handle_client(c) }

