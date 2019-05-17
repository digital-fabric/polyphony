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
def run(socket, opts, handler)
  ctx = connection_context(socket, opts, handler)
  ctx[:parser].on_body = proc { |chunk| handle_body_chunk(ctx, chunk) }

  loop do
    data = socket.readpartial(8192)
    break unless data
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
def connection_context(socket, opts, handler)
  {
    can_upgrade:  true,
    upgrade:      opts[:upgrade],
    count:        0,
    socket:       socket,
    handler:      handler,
    parser:       Http::Parser.new.async!,
    body:         nil
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
  request = Request.new(ctx[:socket], ctx[:parser], ctx[:body])
  ctx[:handler].(request)
  
  if ctx[:parser].keep_alive?
    ctx[:body] = nil
    true
  else
    nil
  end
end

# Upgrades an HTTP 1 connection to HTTP/2 or other protocol on client request
# @param ctx [Hash] connection context
# @return [Boolean] true if connection was upgraded
def upgrade_connection(ctx)
  upgrade_protocol = ctx[:parser].headers['Upgrade']
  return false unless upgrade_protocol

  if ctx[:upgrade] && ctx[:upgrade][upgrade_protocol.to_sym]
    ctx[:upgrade][upgrade_protocol.to_sym].(ctx[:socket], ctx[:parser].headers)
    return true
  end

  return false unless upgrade_protocol == 'h2c'
  
  # upgrade to HTTP/2
  request = http2_upgraded_request(ctx)
  body = ctx[:body] || ''
  HTTP2.upgrade(ctx[:socket], ctx[:handler], request, body)
  true
end

# Returns a request hash for handling by upgraded HTTP 2 connection
# @param ctx [Hash] connection context
# @return [Hash]
def http2_upgraded_request(ctx)
  headers = ctx[:parser].headers
  headers.merge(
    ':scheme'     => 'http',
    ':method'     => ctx[:parser].http_method,
    ':authority'  => headers['Host'],
    ':path'       => ctx[:parser].request_url
  )
end
