# frozen_string_literal: true

export :listen

Net   = import('../net')
HTTP1 = import('./http1')
HTTP2 = import('./http2')

ALPN_PROTOCOLS = %w[h2 http/1.1].freeze
H2_PROTOCOL = 'h2'

async def listen(host, port, opts = {}, &handler)
  opts[:alpn_protocols] = ALPN_PROTOCOLS
  server = await Net.tcp_listen(host, port, opts)

  loop do
    client = await server.accept
    spawn client_task(client, handler) if client
  end
end

async def client_task(client, handler)
  client.no_delay
  
  protocol_module(client).start(client, handler)
end

def protocol_module(socket)
  socket.alpn_protocol == H2_PROTOCOL ? HTTP2 : HTTP1
end
