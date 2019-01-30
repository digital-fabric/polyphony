# frozen_string_literal: true

export :run, :upgrade

require 'http/2'

Request = import('./http2_request')

S_HTTP2_SETTINGS  = 'HTTP2-Settings'

UPGRADE_MESSAGE = <<~HTTP.gsub("\n", "\r\n")
  HTTP/1.1 101 Switching Protocols
  Connection: Upgrade
  Upgrade: h2c

HTTP

def upgrade(socket, handler, request, body)
  interface = prepare(socket, handler)
  settings = request[S_HTTP2_SETTINGS]
  socket.write(UPGRADE_MESSAGE)
  interface.upgrade(settings, request, body)
  client_loop(socket, interface)
end

def prepare(socket, handler)
  ::HTTP2::Server.new.tap do |interface|
    interface.on(:frame) { |bytes| socket << bytes }
    interface.on(:stream) { |stream| start_stream(stream, handler) }
  end
end

def run(socket, opts, handler)
  interface = prepare(socket, handler)
  client_loop(socket, interface)
end

def client_loop(socket, interface)
  loop do
    data = socket.read
    interface << data
    EV.snooze
  end
rescue IOError, SystemCallError => e
  # do nothing
rescue StandardError => e
  puts "error in HTTP2 parse_incoming_data: #{e.inspect}"
  puts e.backtrace.join("\n")
ensure
  socket.close
end

# Handles HTTP 2 stream
# @param stream [HTTP2::Stream] HTTP 2 stream
# @param handler [Proc] request handler
# @return [void]
def start_stream(stream, handler)
  request = Request.new(stream)

  # stream.on(:active) { puts 'client opened new stream' }
  # stream.on(:close)  { puts 'stream closed' }

  stream.on(:headers) { |h| request.set_headers(h) }
  stream.on(:data) { |data| request.add_body_chunk(chunk) }
  stream.on(:half_close) { handler.(request) }
end
