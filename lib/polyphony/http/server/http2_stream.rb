# frozen_string_literal: true

export_default :StreamHandler

require 'http/2'

Request = import './request'
Exceptions = import '../../core/exceptions'

# Manages an HTTP 2 stream
class StreamHandler
  attr_accessor :__next__

  def initialize(stream, &block)
    @stream = stream
    @calling_fiber = Fiber.current
    @stream_fiber = Fiber.new { |req| handle_request(req, &block) }

    # Stream callbacks occur on the connection fiber (see HTTP2::Protocol#each).
    # The request handler is run on a separate fiber for each stream, allowing
    # concurrent handling of incoming requests on the same HTTP/2 connection.
    #
    # The different stream adapter APIs suspend the stream fiber, waiting for
    # stream callbacks to be called. The callbacks, in turn, transfer control to
    # the stream fiber, effectively causing the return of the adapter API calls.
    #
    # Note: the request handler is run once headers are received. Reading the
    # request body, if present, is at the discretion of the request handler.
    # This mirrors the behaviour of the HTTP/1 adapter.
    stream.on(:headers, &method(:on_headers))
    stream.on(:data, &method(:on_data))
    stream.on(:half_close, &method(:on_half_close))
  end

  def handle_request(request, &block)
    error = nil
    block.(request)
    @calling_fiber.transfer
  rescue Exceptions::MoveOn
    # ignore
  rescue Exception => e
    error = e
  ensure
    @done = true
    @calling_fiber.transfer error
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
    if @headers_sent
      @stream.close
    else
      headers[':status'] ||= '204'
      @stream.headers(headers, end_stream: true)
    end
  end

  def stop
    return if @done

    @stream.close
    @stream_fiber.schedule(Polyphony::MoveOn.new)
  end
end
