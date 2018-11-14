# frozen_string_literal: true

export_default :Server

Net   = import('../net')
HTTP1 = import('./http1')
HTTP2 = import('./http2')

# HTTP server implementation
class Server < Net::Server
  # initializes an HTTP server, using the given block as a request handler
  # @param opts [Hash] options
  def initialize(opts = {}, &block)
    super(opts)
    @request_handler = block
    on(:connection, &method(:new_connection))
  end

  ALPN_PROTOCOLS = %w[h2 http/1.1].freeze

  # Starts listening, sets ALPN protocols for a secure server
  # @param opts [Hash] listen options
  # @return [void]
  def listen(opts)
    super(opts.merge(alpn_protocols: ALPN_PROTOCOLS))
  end

  # Handles a new connection
  # @param socket [Net::Socket] connection
  # @return [void]
  def new_connection(socket)
    socket.raw_io.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
    protocol_module(socket).start(socket, @request_handler)
  end

  H2_PROTOCOL = 'h2'

  # Returns the protocol module to be used for handling the connection,
  # depending on whether the socket is secure and on the selected ALPN protocol
  # @param socket [Net::Socket] connection
  # @return [Module]
  def protocol_module(socket)
    protocol = @secure_context && socket.alpn_protocol

    protocol == H2_PROTOCOL ? HTTP2 : HTTP1
  end
end
