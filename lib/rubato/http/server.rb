# frozen_string_literal: true

export :serve

Net   = import('../net')
HTTP1 = import('./http1')
HTTP2 = import('./http2')

ALPN_PROTOCOLS = %w[h2 http/1.1].freeze
H2_PROTOCOL = 'h2'

async def serve(host, port, opts = {}, &handler)
  opts[:alpn_protocols] = ALPN_PROTOCOLS
  server = Net.tcp_listen(host, port, opts)

  while client = server.accept
    spawn client_task(client, handler)
  end
end

async def client_task(client, handler)
  client.no_delay
  
  protocol_module(client).run(client, handler)
end

def protocol_module(socket)
  use_http2 = socket.respond_to?(:alpn_protocol) &&
              socket.alpn_protocol == H2_PROTOCOL
  use_http2 ? HTTP2 : HTTP1
end
