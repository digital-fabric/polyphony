# frozen_string_literal: true

export :Server

Net   = import('./net')
ALPN  = import('./http/alpn')
HTTP1 = import('./http/http1')
HTTP2 = import('./http/http2')

# HTTP server implementation
class Server < Net::Server
  include ALPN
  # include Protocol
  # include Request

  # initializes an HTTP server, using the given block as a request handler
  # @param opts [Hash] options
  def initialize(opts = {}, &block)
    super(opts)
    @request_handler = block
    on(:connection, &method(:new_connection))
  end

  # Starts listening, sets ALPN protocols for a secure server
  # @param opts [Hash] listen options
  # @return [void]
  def listen(opts)
    super(opts)
    ALPN.setup(@secure_context) if @secure_context
  end

  # Handles a new connection
  # @param socket [Net::Socket] connection
  # @return [void]
  def new_connection(socket)
    protocol_module(socket).start(socket, @request_handler)
  end

  H2_PROTOCOL = 'h2'

  def protocol_module(socket)
    protocol = @secure_context && ALPN.alpn_protocol(socket)

    protocol == H2_PROTOCOL ? HTTP2 : HTTP1
  end
end
