# frozen_string_literal: true

export :start

require 'http/parser'

Request = import('./request')
Response = import('./response')
HTTP2 = import('./http2')

# Sets up parsing and handling of request/response cycle
# @param socket [Net::Socket] socket
# @param handler [Proc] request handler
# @return [void]
def start(socket, handler)
  socket.opts[:can_upgrade] = true

  ctx = connection_context(socket, handler)
  ctx[:response] = Response.new(socket) { response_did_finish(ctx) }

  ctx[:parser].on_message_complete = proc { handle_request(ctx) }
  ctx[:parser].on_body = proc { |chunk| handle_body_chunk(ctx, chunk) }

  socket.on(:data) { |data| parse_incoming_data(ctx, data) }
end

# Returns a context hash for the given socket. This hash contains references
# related to the connection and its current state
# @param socket [Net::Socket] socket
# @param handler [Proc] request handler
# @return [Hash]
def connection_context(socket, handler)
  {
    count:    0,
    socket:   socket,
    handler:  handler,
    parser:   Http::Parser.new,
    body:     nil
  }
end

# Resets the connection context and performs cleanup after response was finished
# @param ctx [Hash] connection context
# @return [void]
def response_did_finish(ctx)
  if ctx[:parser].keep_alive?
    ctx[:parser].reset!
    ctx[:response].reset!
    ctx[:body] = nil
  else
    ctx[:socket].close
  end
end

# Parses incoming data
# @param ctx [Hash] connection context
# @return [void]
def parse_incoming_data(ctx, data)
  puts "parse_incoming_data #{ctx[:count]} #{ctx[:socket]}"
  ctx[:parser] << data
rescue StandardError => e
  puts "HTTP 1 parsing error: #{e.inspect}"
  puts e.backtrace.join("\n")
  ctx[:socket].close
end

# Handles request, upgrading the connection if possible
# @param ctx [Hash] connection context
# @return [void]
def handle_request(ctx)
  ctx[:count] += 1
  puts "handle_request #{ctx[:count]} #{ctx[:socket]}"
  return if ctx[:socket].opts[:can_upgrade] && upgrade_connection(ctx)

  ctx[:socket].opts[:can_upgrade] = false
  request = make_request(ctx)
  Request.prepare(request)
  ctx[:handler].(request, ctx[:response])
end

UPGRADE_MESSAGE = [
  'HTTP/1.1 101 Switching Protocols',
  'Connection: Upgrade',
  'Upgrade: h2c',
  '',
  ''
].join("\r\n")

# Upgrades an HTTP 1 connection to HTTP 2 on client request
# @param ctx [Hash] connection context
# @return [Boolean] true if connection was upgraded
def upgrade_connection(ctx)
  return false unless ctx[:parser].headers['Upgrade'] == 'h2c'

  ctx[:socket] << UPGRADE_MESSAGE

  interface = HTTP2.start(ctx[:socket], ctx[:handler])
  settings = ctx[:parser].headers['HTTP2-Settings']
  interface.upgrade(settings, upgraded_request(ctx), ctx[:body] || '')
  true
end

# Returns a request object based on the given context
# @param ctx [Hash] connection context
# @return [Hash]
def make_request(ctx)
  {
    method:       ctx[:parser].http_method,
    request_url:  ctx[:parser].request_url,
    headers:      ctx[:parser].headers,
    body:         ctx[:body]
  }
end

# Returns a request hash for handling by upgraded HTTP 2 connection
# @param ctx [Hash] connection context
# @return [Hash]
def upgraded_request(ctx)
  {
    ':scheme'    => 'http',
    ':method'    => ctx[:parser].http_method,
    ':authority' => ctx[:parser].headers['Host'],
    ':path'      => ctx[:parser].request_url
  }.merge(ctx[:parser].headers)
end

# Adds given chunk to request body
# @param ctx [Hash] connection context
# @return [void]
def handle_body_chunk(context, chunk)
  context[:body] ||= +''
  context[:body] << chunk
end
