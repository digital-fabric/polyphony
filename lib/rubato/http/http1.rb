# frozen_string_literal: true

export :start

require 'http/parser'

Request = import('./request')
Response = import('./response')
HTTP2 = import('./http2')

class Http::Parser
  def async!
    self.on_message_complete = proc { @request_complete = true }
    self
  end

  def parse(data)
    self << data
    return nil unless @request_complete

    @request_complete = nil
    self
  end
end

# Sets up parsing and handling of request/response cycle
# @param socket [Net::Socket] socket
# @param handler [Proc] request handler
# @return [void]
def start(socket, handler)
  socket.opts[:can_upgrade] = true

  ctx = connection_context(socket, handler)
  ctx[:response] = Response.new(socket) { response_did_finish(ctx) }

  # ctx[:parser].on_message_complete = proc { handle_request(ctx) }
  ctx[:parser].on_body = proc { |chunk| handle_body_chunk(ctx, chunk) }

  loop do
    data = await socket.read
    if request = ctx[:parser].parse(data)
      break unless handle_request(ctx)
      EV.snooze
    end
  end
rescue IOError, SystemCallError => e
  # do nothing
ensure
  socket.close
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
    parser:   Http::Parser.new.async!,
    body:     nil,
    request:  {}
  }
end

# Adds given chunk to request body
# @param ctx [Hash] connection context
# @return [void]
def handle_body_chunk(context, chunk)
  context[:body] ||= +''
  context[:body] << chunk
end

# Resets the connection context and performs cleanup after response was finished
# @param ctx [Hash] connection context
# @return [void]
def response_did_finish(ctx)
  if ctx[:parser].keep_alive?
    ctx[:response].reset!
    ctx[:body] = nil
  else
    ctx[:socket].close
  end
end

# Handles request, upgrading the connection if possible
# @param ctx [Hash] connection context
# @return [boolean] true if HTTP 1 loop should continue handling socket
def handle_request(ctx)
  return nil if ctx[:socket].opts[:can_upgrade] && upgrade_connection(ctx)

  # allow upgrading the connection only on first request
  ctx[:socket].opts[:can_upgrade] = false
  request = make_request(ctx)
  Request.prepare(request)
  ctx[:handler].(request, ctx[:response])
  
  if ctx[:parser].keep_alive?
    ctx[:response].reset!
    ctx[:body] = nil
    true
  else
    nil
  end
end

UPGRADE_MESSAGE = [
  'HTTP/1.1 101 Switching Protocols',
  'Connection: Upgrade',
  'Upgrade: h2c',
  '',
  ''
].join("\r\n")

S_EMPTY           = ''
S_UPGRADE         = 'Upgrade'
S_H2C             = 'h2c'
S_HTTP2_SETTINGS  = 'HTTP2-Settings'

# Upgrades an HTTP 1 connection to HTTP 2 on client request
# @param ctx [Hash] connection context
# @return [Boolean] true if connection was upgraded
def upgrade_connection(ctx)
  return false unless ctx[:parser].headers[S_UPGRADE] == S_H2C

  await ctx[:socket].write(UPGRADE_MESSAGE)

  interface = HTTP2.start(ctx[:socket], ctx[:handler])
  settings = ctx[:parser].headers[S_HTTP2_SETTINGS]
  interface.upgrade(settings, upgraded_request(ctx), ctx[:body] || S_EMPTY)
  true
end

def make_request(ctx)
  request = ctx[:request]
  request[:method]       = ctx[:parser].http_method
  request[:request_url]  = ctx[:parser].request_url
  request[:headers]      = ctx[:parser].headers
  request[:body]         = ctx[:body]
  request
end

S_SCHEME      = ':scheme'
S_METHOD      = ':method'
S_AUTHORITY   = ':authority'
S_PATH        = ':path'
S_HTTP        = 'http'
S_HOST        = 'Host'

# Returns a request hash for handling by upgraded HTTP 2 connection
# @param ctx [Hash] connection context
# @return [Hash]
def upgraded_request(ctx)
  {
    S_SCHEME    => S_HTTP,
    S_METHOD    => ctx[:parser].http_method,
    S_AUTHORITY => ctx[:parser].headers[S_HOST],
    S_PATH      => ctx[:parser].request_url
  }.merge(ctx[:parser].headers)
end

