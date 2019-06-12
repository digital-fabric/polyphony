# frozen_string_literal: true

export :serve, :listen, :accept_loop

Net   = import('../net')
HTTP1 = import('./http1_adapter')
HTTP2 = import('./http2_adapter')

ALPN_PROTOCOLS = %w[h2 http/1.1].freeze
H2_PROTOCOL = 'h2'

def serve(host, port, opts = {}, &handler)
  opts[:alpn_protocols] = ALPN_PROTOCOLS
  server = Net.tcp_listen(host, port, opts)
  accept_loop(server, opts, &handler)
end

def listen(host, port, opts = {})
  opts[:alpn_protocols] = ALPN_PROTOCOLS
  Net.tcp_listen(host, port, opts).tap do |socket|
    socket.define_singleton_method(:each) do |&block|
      MODULE.accept_loop(socket, opts, &block)
    end
  end
end

def accept_loop(server, opts, &handler)
  loop do
    client = server.accept
    spin { client_loop(client, opts, &handler) }
  rescue OpenSSL::SSL::SSLError
    # disregard
  end
end

def client_loop(client, opts, &handler)
  client.no_delay rescue nil
  adapter = protocol_adapter(client, opts)
  adapter.each(&handler)
ensure
  client.close rescue nil
end

def protocol_adapter(socket, opts)
  use_http2 = socket.respond_to?(:alpn_protocol) &&
              socket.alpn_protocol == H2_PROTOCOL
  klass = use_http2 ? HTTP2 : HTTP1
  klass.new(socket, opts)
end
