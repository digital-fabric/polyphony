# frozen_string_literal: true

require_relative './extensions/socket'
require_relative './extensions/openssl'

module Polyphony
  
  # A more elegant networking API
  module Net
    class << self

      # Create a TCP connection to the given host and port, returning the new
      # socket. If `opts[:secure]` is true, or if an SSL context is given in
      # `opts[:secure_context]`, a TLS handshake is performed, and an SSLSocket
      # is returned.
      #
      # @param host [String] hostname
      # @param port [Integer] port number
      # @param opts [Hash] options to use
      # @option opts [boolean] :secure use a default context as SSL context, return `SSLSocket` instance
      # @option opts [OpenSSL::SSL::SSLContext] :secure_context SSL context to use, return `SSLSocket` instance
      # @return [TCPSocket, SSLSocket] connected socket
      def tcp_connect(host, port, opts = {})
        socket = TCPSocket.new(host, port)
        if opts[:secure_context] || opts[:secure]
          secure_socket(socket, opts[:secure_context], opts.merge(host: host))
        else
          socket
        end
      end

      # Creates a server socket for accepting incoming connection on the given
      # host and port. If `opts[:secure]` is true, or if an SSL context is given
      # in `opts[:secure_context]`, a TLS handshake is performed, and an
      # SSLSocket is returned.
      #
      # @param host [String] hostname
      # @param port [Integer] port number
      # @param opts [Hash] connection options
      # @return [TCPServer, SSLServer] listening socket
      def tcp_listen(host = nil, port = nil, opts = {})
        host ||= '0.0.0.0'
        raise 'Port number not specified' unless port

        socket = listening_socket_from_options(host, port, opts)
        if opts[:secure_context] || opts[:secure]
          secure_server(socket, opts[:secure_context], opts)
        else
          socket
        end
      end

      # Sets up ALPN negotiation for the given context. The ALPN handler for the
      # context will select the first protocol from the list given by the client
      # that appears in the list of given protocols, according to the specified
      # order.
      # 
      # @param context [SSLContext] SSL context
      # @param protocols [Array] array of supported protocols
      # @return [void]
      def setup_alpn(context, protocols)
        context.alpn_protocols = protocols
        context.alpn_select_cb = lambda do |peer_protocols|
          (protocols & peer_protocols).first
        end
      end

      private

      # Creates a listening `Socket` instance.
      #
      # @param host [String] hostname
      # @param port [Integer] port number
      # @param opts [Hash] connection options
      # @return [Socket] listening socket
      def listening_socket_from_options(host, port, opts)
        ::Socket.new(:INET, :STREAM).tap do |s|
          s.reuse_addr if opts[:reuse_addr]
          s.dont_linger if opts[:dont_linger]
          s.reuse_port if opts[:reuse_port]
          addr = ::Socket.sockaddr_in(port, host)
          s.bind(addr)
          s.listen(opts[:backlog] || Socket::SOMAXCONN)
        end
      end

      # Wraps the given socket with a SSLSocket and performs a TLS handshake.
      #
      # @param socket [Socket] plain socket
      # @param context [SSLContext, nil] SSL context
      # @param opts [Hash] connection options
      # @return [SSLSocket] SSL socket
      def secure_socket(socket, context, opts)
        context ||= OpenSSL::SSL::SSLContext.new
        setup_alpn(context, opts[:alpn_protocols]) if opts[:alpn_protocols]
        socket = secure_socket_wrapper(socket, context)

        socket.tap do |s|
          s.hostname = opts[:host] if opts[:host]
          s.connect
          s.post_connection_check(opts[:host]) if opts[:host]
        end
      end

      # Wraps the given socket with an SSLSocket.
      #
      # @param socket [Socket] plain socket
      # @param context [SSLContext] SSL context
      # @return [SSLSocket] SSL socket
      def secure_socket_wrapper(socket, context)
        if context
          OpenSSL::SSL::SSLSocket.new(socket, context)
        else
          OpenSSL::SSL::SSLSocket.new(socket)
        end
      end

      # Wraps the given socket with an SSLServer, setting up ALPN from the given
      # options.
      #
      # @param socket [Socket] plain socket
      # @param context [SSLContext] SSL context
      # @param opts [Hash] options
      # @return [SSLServer] SSL socket
      def secure_server(socket, context, opts)
        setup_alpn(context, opts[:alpn_protocols]) if opts[:alpn_protocols]
        OpenSSL::SSL::SSLServer.new(socket, context)
      end
    end
  end
end
