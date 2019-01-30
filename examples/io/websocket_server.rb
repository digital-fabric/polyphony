# frozen_string_literal: true

require 'modulation'
require 'digest/sha1'
require 'base64'
require 'websocket'
require 'json'

STDOUT.sync = true

Polyphony = import('../../lib/polyphony')
HTTPServer = import('../../lib/polyphony/http/server')

def send_ws(client, version, data)
  frame = WebSocket::Frame::Outgoing::Server.new(
    version: version, data: data, type: :text
  )
  client << frame.to_s
end

module RPC
  class << self
    def add(x, y); x + y; end
    def mul(x, y); x * y; end
  end
end

def handle_msg(client, version, msg)
  op = msg[:op].to_sym
  if RPC.respond_to?(op)
    result = RPC.send(op, *msg[:args])
    send_ws(client, version, {result: result}.to_json)
  end
end

S_WS_GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'

def websocket_client(client, headers)
  key = headers['Sec-WebSocket-Key']
  version = headers['Sec-WebSocket-Version'].to_i
  accept = Digest::SHA1.base64digest([key, S_WS_GUID].join)
  client << "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: #{accept}\r\n\r\n"
  
  frame = WebSocket::Frame::Incoming::Server.new(version: version)
  loop do
    data = client.read
    frame << data
    while data = frame.next
      data = data.to_s
      if (msg = JSON.parse(data, symbolize_names: true) rescue nil)
        handle_msg(client, version, msg)
      end
    end
  end
end

opts = {
  reuse_addr: true, dont_linger: true,
  upgrade: {
    websocket: ->(*args) { websocket_client(*args) }
  }
}

server = HTTPServer.serve('0.0.0.0', 1234, opts) do |req|
  req.respond("Hello world!\n")
end

puts "pid: #{Process.pid}"
puts "Listening on port 1234..."
server.await
puts "bye bye"

