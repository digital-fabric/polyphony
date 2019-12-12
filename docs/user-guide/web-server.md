# Web Server

Polyphony's web server functionality offers a powerful and flexible way to
create Ruby-based web servers and web applications. In addition to supporting
both HTTP 1 and HTTP 2, it supports seamless Websocket upgrades (and indeed
arbitrary protocol upgrade), TLS termination, and automatic ALPN-based protocol
selection. In addition, it includes a Rack adapter for running Rack
applications. Polyphony's web server offers excellent performance
characteristics, in terms of throughput, memory consumption and scalability
(benchmarks are forthcoming).

What makes Polyphony's web server design stand out is the fact that incoming
requests can be processed immediately upon receiving the complete headers,
without needing to wait for the entire request body to be received. This design
allows web applications to properly buffer uploads of large files without
consuming large amounts of RAM, as well as reject requests without waiting for
the entire request body.

## A basic web server

```ruby
require 'polyphony/http'

Polyphony::HTTP::Server.serve('0.0.0.0', 1234) do |request|
  request.respond("Hello world!\n")
end
```

Note that requests are handled using a callback block which takes a single
argument. The `request` object provides the entire API for responding to the
client.

Each client connection will be handled in a separate coprocess, allowing
concurrent processing of incoming requests.

## HTTP 2 support

HTTP 2 support is baked in to the server, which supports both HTTP 2 upgrades
(for example on a non-encrypted connection) and ALPN-based protocol selection,
in a completely effortless manner.

Since HTTP 2 connections are multiplexed, allowing multiple concurrent requests
on a single connection, each HTTP 2 stream is handled in a separate coprocess.

## TLS termination

TLS termination can be handled by passing a `secure_context` option to the
server:

```ruby
require 'polyphony/http'
require 'localhost/authority'

authority = Localhost::Authority.fetch
opts = { secure_context: authority.server_context }

Polyphony::HTTP::Server.serve('0.0.0.0', 1234, opts) do |request|
  request.respond("Hello world!\n")
end
```

## Websockets && HTTP upgrades

Polyphony's web server makes it really easy to integrate websocket communication
with normal HTTP processing:

```ruby
require 'polyphony/http'
require 'polyphony/websocket'

ws_handler = Polyphony::Websocket.handler do |ws|
  while (msg = ws.recv)
    ws << "you said: #{msg}"
  end
end

opts = {
  upgrade: { websocket: ws_handler }
}

Polyphony::HTTP::Server.serve('0.0.0.0', 1234, opts) do |request|
  request.respond("Hello world!\n")
end
```

Polyphony also supports general-purpose HTTP upgrades using the same mechanism:

```ruby
require 'polyphony/http'

opts = {
  upgrade: {
    echo: ->(conn) {
      while (msg = conn.gets)
        conn << "You said: #{msg}"
      end
    }
  }
}

Polyphony::HTTP::Server.serve('0.0.0.0', 1234, opts) do |request|
  request.respond("Hello world!\n")
end
```

## Sending HTTP responses

The response API provides multiple ways of responding, with or without a body,
and enables streaming (using chunked encoding for HTTP/1.1 connections). Here's
an example of an SSE response:

```ruby
require 'polyphony/http'

def sse_response(request)
  request.send_headers('Content-Type': 'text/event-stream')
  move_on_after(10) {
    loop {
      request.send_chunk("data: #{Time.now}\n\n")
      sleep 1
    }
  }
ensure
  request.send_chunk("retry: 0\n\n", done: true)
end

Polyphony::HTTP::Server.serve('0.0.0.0', 1234, &method(:sse_response))
```

