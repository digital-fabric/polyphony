# frozen_string_literal: true

export_default :StreamHandler

require 'http/2'

Request = import './request'
FiberPool = import '../../core/fiber_pool'

class StreamHandler
  attr_accessor :__next__

  def initialize(stream, &block)
    @stream = stream
    @stream_fiber = FiberPool.allocate(&block)

    # stream callbacks occur on connection fiber
    stream.on(:headers, &method(:on_headers))
    stream.on(:data, &method(:on_data))
    stream.on(:half_close, &method(:on_half_close))
  end

  def on_headers(headers)
    @request = Request.new(headers.to_h, self)
    @stream_fiber.transfer(@request)
  end

  def on_data(data)
    if @waiting_for_body_chunk
      @waiting_for_body_chunk = nil
      @stream_fiber.transfer(data)
    else
      @request.buffer_body_chunk(data)
    end
  end

  def on_half_close
    if @waiting_for_body_chunk
      @waiting_for_body_chunk = nil
      @stream_fiber.transfer(nil)
    elsif @waiting_for_half_close
      @waiting_for_half_close = nil
      @stream_fiber.transfer(nil)
    else
      @request.complete!
    end
  end

  def protocol
    'h2'
  end

  def get_body_chunk
    # called in the context of the stream fiber
    return nil if @request.complete?

    @waiting_for_body_chunk = true
    # the chunk (or an exception) will be returned once the stream fiber is
    # resumed
    suspend
  ensure
    @waiting_for_body_chunk = nil
  end

  # Wait for request to finish
  def consume_request
    return if @request.complete?

    @waiting_for_half_close = true
    suspend
  ensure
    @waiting_for_half_close = nil
  end

  # response API
  def respond(chunk, headers)
    headers[':status'] ||= '200'
    @stream.headers(headers, end_stream: false)
    @stream.data(chunk, end_stream: true)
    @headers_sent = true
  end

  def send_headers(headers, empty_response = false)
    return if @headers_sent

    headers[':status'] ||= (empty_response ? 204 : 200).to_s
    @stream.headers(headers, end_stream: false)
    @headers_sent = true
  end

  def send_chunk(chunk, done: false)
    send_headers({}, false) unless @headers_sent
    @stream.data(chunk, end_stream: done)
  end
  
  def finish
    unless @headers_sent
      headers[':status'] ||= '204'
      @stream.headers(headers, end_stream: true)
    else
      @stream.close
    end
  end
end
