# frozen_string_literal: true

export :handler

require 'digest/sha1'
require 'websocket'

# Websocket connection
class WebsocketConnection
  def initialize(client, headers)
    @client = client
    @headers = headers
    setup(headers)
  end

  S_WS_GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'
  UPGRADE_RESPONSE = <<~HTTP.gsub("\n", "\r\n")
    HTTP/1.1 101 Switching Protocols
    Upgrade: websocket
    Connection: Upgrade
    Sec-WebSocket-Accept: %<accept>s

  HTTP

  def setup(headers)
    key = headers['Sec-WebSocket-Key']
    @version = headers['Sec-WebSocket-Version'].to_i
    accept = Digest::SHA1.base64digest([key, S_WS_GUID].join)
    @client << format(UPGRADE_RESPONSE, accept: accept)

    @reader = ::WebSocket::Frame::Incoming::Server.new(version: @version)
  end

  def recv
    loop do
      data = @client.readpartial(8192)
      break nil unless data

      @reader << data
      if (msg = @reader.next)
        break msg.to_s
      end
    end
  end

  def send(data)
    frame = ::WebSocket::Frame::Outgoing::Server.new(
      version: @version, data: data, type: :text
    )
    @client << frame.to_s
  end
  alias_method :<<, :send
end

def handler(&block)
  proc { |client, header|
    block.(WebsocketConnection.new(client, header))
  }
end
