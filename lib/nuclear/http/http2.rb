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

  def protocol
    HTTP2_PROTOCOL
  end

  def reset!
    @status_code = 200
    @headers = {}
    @headers_sent = nil
  end

  def set_header(key, value)
    @headers[key.to_s] = value.to_s
  end

  def write_head(status_code = 200, headers = {})
    raise 'Headers already sent' if @headers_sent

    headers.each { |k, v| @headers[k.to_s] = v.to_s }
  end

  def send_headers
    headers = { ':status' => @status_code.to_s }.merge(@headers)
    @stream.headers(headers, end_stream: false)
    @headers_sent = true
  end

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

def set_request_headers(request, headers)
  h = request[:headers] = Hash[*headers.flatten]
  request[:method]      = h[':method']
  request[:request_url] = h[':path']
  request[:scheme]      = h[':scheme']
end

def handle_body_chunk(request, chunk)
  request[:body] ||= +''
  request[:body] << chunk
end

def finalize_request(stream, request, handler)
  response = HTTP2Response.new(stream)
  Request.prepare(request)
  handler.(request, response)
end
