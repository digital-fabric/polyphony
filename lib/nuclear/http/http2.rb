# frozen_string_literal: true

export :start

require 'http/2'

Request = import('./request')
Response = import('./response')

# HTTP 2.0 Response
class HTTP2Response < Response
  def initialize(stream, &on_finished)
    @stream = stream
    @on_finished = on_finished
    reset!
  end

  HTTP2_PROTOCOL = 'h2'

  # Returns 'h2' as the protocol used
  # @return [String]
  def protocol
    HTTP2_PROTOCOL
  end

  # Resets the response so it can be reused
  # @return [void]
  def reset!
    @status_code = 200
    @headers = {}
    @headers_sent = nil
  end

  # Adds a response header
  # @param key [Symbol, String] header key
  # @param value [any] header value
  # @return [void]
  def set_header(key, value)
    @headers[key.to_s] = value.to_s
  end

  # Sets the status code and response headers. The response headers will not
  # actually be sent until #send_headers is called.
  # @param status_code [Integer] HTTP status code
  # @param headers [Hash] response headers
  # @return [void]
  def write_head(status_code = 200, headers = {})
    @status_code = status_code
    raise 'Headers already sent' if @headers_sent

    headers.each { |k, v| @headers[k.to_s] = v.to_s }
  end

  # Sends status code and headers
  # @return [void]
  def send_headers
    headers = { ':status' => @status_code.to_s }.merge(@headers)
    @stream.headers(headers, end_stream: false)
    @headers_sent = true
  end

  # Sends response body, optionally finishing the response
  # @param data [String] response body
  # @param finish [Boolean] whether the response is finished
  # @return [void]
  def send(data, finish)
    @stream.data(data, end_stream: finish)
  end
end

# Sets up HTTP 2 parser
# @param socket [Net::Socket] socket
# @return [HTTP2::Server] HTTP2 interface
def start(socket, handler)
  ::HTTP2::Server.new.tap do |interface|
    socket.on(:data) { |data| parse_incoming_data(socket, interface, data) }

    interface.on(:frame) { |bytes| socket << bytes }
    interface.on(:stream) { |stream| start_stream(stream, handler) }
  end
end

# Parses incoming data for HTTP 2 connection
# @param socket [Net::Socket] connection
# @param interface [HTTP2::Server] associated HTTP 2 parser
# @param data [String] data received from connection
# @return [void]
def parse_incoming_data(socket, interface, data)
  interface << data
rescue StandardError => e
  puts "error in HTTP2 parse_incoming_data: #{e}"
  puts e.backtrace.join("\n")
  socket.close
end

# Handles HTTP 2 stream
# @param stream [HTTP2::Stream] HTTP 2 stream
# @param handler [Proc] request handler
# @return [void]
def start_stream(stream, handler)
  request = {}

  # stream.on(:active) { puts 'client opened new stream' }
  # stream.on(:close)  { puts 'stream closed' }

  stream.on(:headers) { |h| set_request_headers(request, h) }
  stream.on(:data) { |data| handle_body_chunk(request, data) }
  stream.on(:half_close) { finalize_request(stream, request, handler) }
end

# Sets request headers
# @param request [Hash] request object
# @param headers [Array<Array>] array of headers as received from h2 interface
# @return [void]
def set_request_headers(request, headers)
  h = request[:headers] = Hash[*headers.flatten]
  request[:method]      = h[':method']
  request[:request_url] = h[':path']
  request[:scheme]      = h[':scheme']
end

# Handles body chunk received from stream
# @param request [Hash] request object
# @param chunk [String] body chunk
# @return [void]
def handle_body_chunk(request, chunk)
  request[:body] ||= +''
  request[:body] << chunk
end

# Finalizes request, passing it to given handler
# @param stream [HTTP2::Stream] stream
# @param request [Hash] request object
# @param handler [Proc] handler proc
def finalize_request(stream, request, handler)
  response = HTTP2Response.new(stream)
  Request.prepare(request)
  handler.(request, response)
end
