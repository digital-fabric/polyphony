# frozen_string_literal: true

require_relative './extensions/socket'
require_relative './extensions/openssl'

module Polyphony
  # A more elegant networking API
  module Net
    class << self
      def tcp_connect(host, port, opts = {})
        socket = ::Socket.new(:INET, :STREAM).tap do |s|
          addr = ::Socket.sockaddr_in(port, host)
          s.connect(addr)
        end
        if opts[:secure_context] || opts[:secure]
          secure_socket(socket, opts[:secure_context], opts.merge(host: host))
        else
          socket
        end
      end

      def tcp_listen(host = nil, port = nil, opts = {})
        host ||= '0.0.0.0'
        raise 'Port number not specified' unless port

        socket = socket_from_options(host, port, opts)
        if opts[:secure_context] || opts[:secure]
          secure_server(socket, opts[:secure_context], opts)
        else
          socket
        end
      end

      def socket_from_options(host, port, opts)
        ::Socket.new(:INET, :STREAM).tap do |s|
          s.reuse_addr if opts[:reuse_addr]
          s.dont_linger if opts[:dont_linger]
          s.reuse_port if opts[:reuse_port]
          addr = ::Socket.sockaddr_in(port, host)
          s.bind(addr)
          s.listen(opts[:backlog] || Socket::SOMAXCONN)
        end
      end

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

      def secure_socket_wrapper(socket, context)
        if context
          OpenSSL::SSL::SSLSocket.new(socket, context)
        else
          OpenSSL::SSL::SSLSocket.new(socket)
        end
      end

      def secure_server(socket, context, opts)
        setup_alpn(context, opts[:alpn_protocols]) if opts[:alpn_protocols]
        OpenSSL::SSL::SSLServer.new(socket, context)
      end

      def setup_alpn(context, protocols)
        context.alpn_protocols = protocols
        context.alpn_select_cb = lambda do |peer_protocols|
          (protocols & peer_protocols).first
        end
      end
    end
  end
end
