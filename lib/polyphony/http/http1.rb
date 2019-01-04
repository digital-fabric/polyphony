# frozen_string_literal: true

export :run

require 'http/parser'

Request = import('./http1_request')
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
def run(socket, handler)
  ctx = connection_context(socket, handler)
  ctx[:parser].on_body = proc { |chunk| handle_body_chunk(ctx, chunk) }

  loop do
    data = socket.read
    if ctx[:parser].parse(data)
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
    can_upgrade:  true,
    count:        0,
    socket:       socket,
    handler:      handler,
    parser:       Http::Parser.new.async!,
    body:         nil,
    request:      Request.new
  }
end

# Adds given chunk to request body
# @param ctx [Hash] connection context
# @return [void]
def handle_body_chunk(context, chunk)

  context[:body] ||= +''
  context[:body] << chunk
end

# Handles request, upgrading the connection if possible
# @param ctx [Hash] connection context
# @return [boolean] true if HTTP 1 loop should continue handling socket
def handle_request(ctx)
  return nil if ctx[:can_upgrade] && upgrade_connection(ctx)

  # allow upgrading the connection only on first request
  ctx[:can_upgrade] = false
  ctx[:request].setup(ctx[:socket], ctx[:parser], ctx[:body])
  ctx[:handler].(ctx[:request])
  
  if ctx[:parser].keep_alive?
    ctx[:body] = nil
    true
  else
    nil
  end
end

S_EMPTY           = ''
S_UPGRADE         = 'Upgrade'
S_H2C             = 'h2c'
S_SCHEME          = ':scheme'
S_METHOD          = ':method'
S_AUTHORITY       = ':authority'
S_PATH            = ':path'
S_HTTP            = 'http'
S_HOST            = 'Host'

# Upgrades an HTTP 1 connection to HTTP 2 on client request
# @param ctx [Hash] connection context
# @return [Boolean] true if connection was upgraded
def upgrade_connection(ctx)
  return false unless ctx[:parser].headers[S_UPGRADE] == S_H2C

  request = http2_upgraded_request(ctx)
  body = ctx[:body] || S_EMPTY
  HTTP2.upgrade(ctx[:socket], ctx[:handler], request, body)
  true
end

# Returns a request hash for handling by upgraded HTTP 2 connection
# @param ctx [Hash] connection context
# @return [Hash]
def http2_upgraded_request(ctx)
  headers = ctx[:parser].headers
  headers.merge(
    S_SCHEME    => S_HTTP,
    S_METHOD    => ctx[:parser].http_method,
    S_AUTHORITY => headers[S_HOST],
    S_PATH      => ctx[:parser].request_url
  )
end
