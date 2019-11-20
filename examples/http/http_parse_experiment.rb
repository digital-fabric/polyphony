# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

require 'http/parser'
require 'fiber'

i, o = IO.pipe

class ParseLoop
  def initialize(conn)
    @parser = HTTP::Parser.new(self)
    @conn = conn
    @parse_fiber = Fiber.new do
      while (data = conn.readpartial(8192))
        @parser << data
        snooze
      end
    rescue StandardError => e
      conn.close
      e
    ensure
      @message_in_train = nil
    end
    @state = nil
  end

  def on_headers_complete(headers)
    @calling_fiber.transfer(headers)
  end

  def on_body(chunk)
    @calling_fiber.transfer(chunk) if @read_body
  end

  def on_message_begin
    @message_in_train = true
  end

  def on_message_complete
    @message_in_train = nil
    @calling_fiber.transfer nil
  end

  def parse_headers
    @calling_fiber = Fiber.current
    @parse_fiber.safe_transfer
  end

  def parse_body_chunk
    @calling_fiber = Fiber.current
    @read_body = true
    @parse_fiber.safe_transfer
  end

  def consume_request
    return unless @message_in_train

    @calling_fiber = Fiber.current
    @read_body = false
    @parse_fiber.safe_transfer while @message_in_train
  end

  def alive?
    @parse_fiber.alive?
  end

  def busy?
    @message_in_train
  end
end

def handle(parser)
  headers = parser.parse_headers
  return unless headers

  puts "headers: #{headers.inspect}"
  headers['Content-Length']
  # if content_length && (content_length.to_i < 1000)
  while (chunk = parser.parse_body_chunk)
    puts "chunk: #{chunk.inspect}"
  end
  # else
  #   parser.consume_request
  # end
  puts 'end of request'
rescue StandardError => e
  puts "error: #{e.inspect}"
  raise e
end

writer = spin do
  o << "POST / HTTP/1.1\r\nHost: example.com\r\nContent-Length: 6\r\n\r\n"
  o << 'Hello!'

  o << "POST / HTTP/1.1\r\nHost: example.com\r\n\r\n"

  # o << "POST / HTTP/1.1\r\nHost: example.com\r\nContent-Length: 8192\r\n\r\n"
  # o << ("Bye!" * 2048)

  o << "POST / HTTP/1.1\r\nHost: example.com\r\nContent-Length: 4\r\n\r\n"
  o << 'Bye!'

  begin
    (o << ('BLAH' * 100_000))
  rescue StandardError
    nil
  end
  o.close
end

begin
  parse_loop = ParseLoop.new(i)
  while parse_loop.alive?
    puts '*' * 40
    handle(parse_loop)
  end
rescue StandardError => e
  writer.stop
  puts "#{e.class}: #{e.message}"
  puts e.backtrace
end
