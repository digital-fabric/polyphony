# frozen_string_literal: true

export_default :Protocol

require 'http/2'

Request = import('./request')

class StreamWrapper
  def initialize(stream, parse_fiber)
    @stream = stream
    @parse_fiber = parse_fiber
    @parsing = true

    stream.on(:data) { |data| on_body(data) }
    stream.on(:half_close) { on_message_complete }
  end

  def protocol
    'h2'
  end

  # Reads body chunk from connection
  def get_body_chunk
    @calling_fiber = Fiber.current
    @read_body = true
    @parse_fiber.safe_transfer
  end

  # Wait for request to finish
  def consume_request
    return unless @parsing

    @calling_fiber = Fiber.current
    @read_body = false
    @parse_fiber.safe_transfer while @parsing
  end

  def on_body(data)
    @calling_fiber.transfer(data) if @read_body
  end

  def on_message_complete
    @parsing = false
    @calling_fiber.transfer nil
  end

  # response API
  def respond(chunk, headers)
    consume_request if @parsing

    headers[':status'] ||= '200'
    @stream.headers(headers, end_stream: false)
    @stream.data(chunk, end_stream: true)
    @headers_sent = true
  end

  def send_headers(headers, empty_response = false)
    return if @headers_sent

    consume_request if @parsing

    headers[':status'] ||= (empty_response ? 204 : 200).to_s
    @stream.headers(headers, end_stream: false)
    @headers_sent = true
  end

  def send_chunk(chunk, done: false)
    send_headers({}, false) unless @headers_sent
    @stream.data(chunk, end_stream: done)
  end
  
  def finish
    consume_request if @parsing

    unless @headers_sent
      headers[':status'] ||= '204'
      @stream.headers(headers, end_stream: true)
    else
      @stream.close
    end
  end
end

class Protocol
  def self.upgrade_each(socket, opts, headers, &block)
    adapter = new(socket, opts, headers)
    adapter.each(&block)
  end

  def initialize(conn, opts, upgrade_headers = nil)
    @conn = conn  
    @opts = opts

    @interface = ::HTTP2::Server.new
    @interface.on(:frame) { |bytes| conn << bytes }
    @interface.on(:stream) { |stream| start_stream(stream) }
    @parse_fiber = Fiber.new { parse_loop(upgrade_headers) }
  end

  def start_stream(stream)
    stream.on(:headers) do |headers|
      @calling_fiber.transfer([stream, headers.to_h])
    end
  end

  def parse_loop(upgrade_headers)
    upgrade(upgrade_headers) if upgrade_headers
      
    while (data = @conn.readpartial(8192))
      @interface << data
      snooze
    end
    @calling_fiber.transfer nil
  rescue SystemCallError, IOError
    # ignore
    @calling_fiber.transfer nil
  rescue => error
    # an error return value will be raised by the receiving fiber
    @calling_fiber.transfer error
  end

  # request API
  
  UPGRADE_MESSAGE = <<~HTTP.gsub("\n", "\r\n")
  HTTP/1.1 101 Switching Protocols
  Connection: Upgrade
  Upgrade: h2c

  HTTP

def upgrade(headers)
    settings = headers['HTTP2-Settings']
    @conn << UPGRADE_MESSAGE
    @interface.upgrade(settings, headers, '')
  end

  # Iterates over incoming requests
  def each(&block)
    can_upgrade = true
    while @parse_fiber.alive?
      stream, headers = get_headers
      break unless stream
      wrapper = StreamWrapper.new(stream, @parse_fiber)
      request = Request.new(headers, wrapper)
      Fiber.new { block.(request) }.resume
    end
  ensure
    @conn.close rescue nil
  end

  # Reads headers from connection
  def get_headers
    @calling_fiber = Fiber.current
    @parse_fiber.safe_transfer
  end
end