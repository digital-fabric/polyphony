# frozen_string_literal: true

require 'bundler/inline'

gemfile do
  source 'https://rubygems.org'
  gem 'h1p', path: '../h1p'
  # gem 'polyphony', path: '.'
end

# require 'polyphony'
require 'h1p'

module ::Kernel
  def trace(*args)
    STDOUT << format_trace(args)
  end

  def format_trace(args)
    if args.first.is_a?(String)
      if args.size > 1
        format("%s: %p\n", args.shift, args)
      else
        format("%s\n", args.first)
      end
    else
      format("%p\n", args.size == 1 ? args.first : args)
    end
  end

  def monotonic_clock
    ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
  end
end

def handle_client(conn)
  Thread.new do
    reader = proc do |len, buf, buf_pos|
      trace(len:, buf:, buf_pos:)
      s = conn.readpartial(len)
      buf ? (buf << s) : +s
    rescue EOFError
      nil
    end
    parser = H1P::Parser.new(reader, :server)
    # parser = H1P::Parser.new(conn, :server)
    while (headers = parser.parse_headers)
      parser.read_body unless parser.complete?
      conn << "HTTP/1.1 200 OK\r\nContent-Length: 14\r\n\r\nHello, world!\n"
    end
  rescue Errno::ECONNRESET, Errno::EPIPE
    # ignore
  rescue H1P::Error
    puts 'Got invalid request, closing connection...'
  ensure
    parser = nil
    conn.close rescue nil
  end
end

puts "Serving HTTP on port 1234..."
s = TCPServer.new('0.0.0.0', 1234)
while true
  c = s.accept
  handle_client(c)
end
