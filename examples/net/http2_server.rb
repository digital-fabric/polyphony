#!/usr/bin/env ruby
# frozen_string_literal: true

require 'modulation'
require 'http/2'
require 'localhost/authority'

Core        = import('../../lib/nuclear/core')
Net         = import('../../lib/nuclear/net')
include Core::Async

def connection_upgraded(socket)
  puts "connection_upgraded (ALPN protocol: #{socket.raw_io.alpn_protocol.inspect})"
  conn = HTTP2::Server.new
  conn.on(:frame) {|bytes| socket.write(bytes)}
  socket.on(:data) do |data|
    # puts "Received data: #{data}"
    # puts "Received bytes: #{data.unpack("H*").first}"
    begin
      conn << data
    rescue => e
      p e.inspect
      # puts e.backtrace.join("\n")
      socket.close
    end
  end
  conn.on(:stream) do |stream|
    req, buffer = {}, ''

    # stream.on(:active) { puts 'client opened new stream' }
    # stream.on(:close)  { puts 'stream closed' }

    stream.on(:headers) do |h|
      req = Hash[*h.flatten]
      # puts "request headers: #{h}"
    end

    stream.on(:data) do |d|
      # puts "payload chunk: <<#{d}>>"
      buffer << d
    end

    stream.on(:half_close) do
      # puts 'client closed its end of the stream'

      # puts "request: #{req.inspect}"

      response = nil
      if req[':method'] == 'POST'
        # puts "Received POST request, payload: #{buffer}"
        response = "Hello HTTP 2.0! POST payload: #{buffer}"
      else
        # puts 'Received GET request'
        response = 'Hello HTTP 2.0! GET request'
      end

      stream.headers({
        ':status' => '200',
        'content-length' => response.bytesize.to_s,
        'content-type' => 'text/plain',
      }, end_stream: false)

      stream.data(response)
    end
  end
end

def http2_connection(socket)
  connection_upgraded(socket)
  # parser = Http::Parser.new
  # parser.on_message_complete = -> { handle_request(socket, parser) }

  # socket.on(:data) do |data|
  #   parse_incoming_data(socket, parser, data)
  # end
end

server = Net::Server.new
server.on(:connection) do |socket|
  async { http2_connection(socket) }
end

context = Localhost::Authority.fetch.server_context
puts "*" * 40
context.alpn_protocols = ["http/1.1", "spdy/2", "h2"]

context.alpn_select_cb = lambda do |protocols|
  # inspect the protocols and select one
  puts "select: #{protocols.inspect}"
  protocols.first
end
server.listen(port: 1234, secure_context: context)
puts "listening on port 1234"

