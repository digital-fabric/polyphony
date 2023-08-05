# frozen_string_literal: true

require 'bundler/inline'

gemfile do
  source 'https://rubygems.org'
  gem 'http_parser.rb'
  gem 'polyphony', path: '.'
end

require 'polyphony'
require 'http_parser.rb'

def handle_client(conn)
  spin do
    parser = Http::Parser.new
    done = false
    headers = nil
    parser.on_headers_complete = proc do |h|
      headers = h
      headers[':method'] = parser.http_method
      headers[':path'] = parser.request_url
    end
    parser.on_message_complete = proc { done = true }

    while true # assuming persistent connection
      conn.read_loop do |msg|
        parser << msg
        break if done
      end

      conn << "HTTP/1.1 200 OK\r\nContent-Length: 14\r\n\r\nHello, world!\n"
      done = false
      headers = nil
    end
  rescue Errno::ECONNRESET, Errno::EPIPE
    # ignore
  ensure
    parser = nil
    conn.close rescue nil
  end
end

puts "Serving HTTP on port 1234..."
TCPServer.new('0.0.0.0', 1234).accept_loop { |c| handle_client(c) }
