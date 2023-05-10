# frozen_string_literal: true

require 'bundler/inline'

gemfile do
  source 'https://rubygems.org'
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

      parser.read_body unless parser.complete?

      conn << "HTTP/1.1 200 OK\r\nContent-Length: 14\r\n\r\nHello, world!\n"
    end
  rescue Errno::ECONNRESET
    # ignore
  rescue H1P::Error
    puts 'Got invalid request, closing connection...'
  ensure
    conn.close rescue nil
  end
end

puts "Serving HTTP on port 1234..."
TCPServer.new('0.0.0.0', 1234).accept_loop { |c| handle_client(c) }
