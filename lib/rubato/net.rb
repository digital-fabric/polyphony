# frozen_string_literal: true

export  :tcp_connect,
        :tcp_listen,
        :getaddrinfo

import('./extensions/socket')
import('./extensions/ssl')

def tcp_connect(host, port, opts = {})
  socket = ::Socket.new(:INET, :STREAM).tap { |s|
    addr = ::Socket.sockaddr_in(port, host)
    s.connect(addr)
  }
  if opts[:secure_context] || opts[:secure]
    secure_socket(socket, opts[:secure_context], opts)
  else
    socket
  end
end

def tcp_listen(host = nil, port = nil, opts = {})
  host ||= '0.0.0.0'
  raise "Port number not specified" unless port
  socket = ::Socket.new(:INET, :STREAM).tap { |s|
    s.reuse_addr if opts[:reuse_addr]
    s.dont_linger if opts[:dont_linger]
    addr = ::Socket.sockaddr_in(port, host)
    s.bind(addr)
    s.listen(0)
  }
  if opts[:secure_context] || opts[:secure]
    secure_server(socket, opts[:secure_context], opts)
  else
    socket
  end
end

DEFAULT_SSL_CONTEXT = OpenSSL::SSL::SSLContext.new
# DEFAULT_SSL_CONTEXT.set_params(verify_mode: OpenSSL::SSL::VERIFY_PEER)

def secure_socket(socket, context, opts)
  context ||= DEFAULT_SSL_CONTEXT
  setup_alpn(context, opts[:alpn_protocols]) if opts[:alpn_protocols]
  OpenSSL::SSL::SSLSocket.new(socket, context).tap { |s| s.connect }
end

def secure_server(socket, context, opts)
  context ||= DEFAULT_SSL_CONTEXT
  setup_alpn(context, opts[:alpn_protocols]) if opts[:alpn_protocols]
  OpenSSL::SSL::SSLServer.new(socket, context)
end

def setup_alpn(context, protocols)
  context.alpn_protocols = protocols
  context.alpn_select_cb = ->(peer_protocols) {
    (protocols & peer_protocols).first
  }
end
