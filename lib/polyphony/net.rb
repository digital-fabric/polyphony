# frozen_string_literal: true

export  :tcp_connect,
        :tcp_listen

import('./extensions/socket')
import('./extensions/openssl')

def tcp_connect(host, port, opts = {})
  socket = ::Socket.new(:INET, :STREAM).tap { |s|
    addr = ::Socket.sockaddr_in(port, host)
    s.connect(addr)
  }
  if opts[:secure_context] || opts[:secure]
    secure_socket(socket, opts[:secure_context], opts.merge(host: host))
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

def secure_socket(socket, context, opts)
  setup_alpn(context, opts[:alpn_protocols]) if context && opts[:alpn_protocols]
  socket = context ?
    OpenSSL::SSL::SSLSocket.new(socket, context) :
    OpenSSL::SSL::SSLSocket.new(socket)
  
  socket.tap do |s|
    s.hostname = opts[:host] if opts[:host]
    s.connect
    s.post_connection_check(opts[:host]) if opts[:host]
  end
end

def secure_server(socket, context, opts)
  setup_alpn(context, opts[:alpn_protocols]) if opts[:alpn_protocols]
  OpenSSL::SSL::SSLServer.new(socket, context)
end

def setup_alpn(context, protocols)
  context.alpn_protocols = protocols
  context.alpn_select_cb = ->(peer_protocols) {
    (protocols & peer_protocols).first
  }
end
