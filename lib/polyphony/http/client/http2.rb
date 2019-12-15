# frozen_string_literal: true

export_default :HTTP1Adapter

require 'http/parser'

Response = import './response'

# HTTP 1 adapter
class HTTP1Adapter
  def initialize(socket)
    @socket = socket
    @parser = HTTP::Parser.new(self)
  end

  def request(ctx)
    unless state[:http2_client]
      socket = state[:socket]
      state[:http2_client] = client = HTTP2::Client.new
      client.on(:frame) { |bytes| socket << bytes }
    end

    stream = state[:http2_client].new_stream # allocate new stream

    headers = {
      ':method'    => ctx[:method].to_s,
      ':scheme'    => ctx[:uri].scheme,
      ':authority' => [ctx[:uri].host, ctx[:uri].port].join(':'),
      ':path'      => ctx[:uri].request_uri
    }
    headers.merge!(ctx[:opts][:headers]) if ctx[:opts][:headers]

    if ctx[:opts][:payload]
      stream.headers(headers, end_stream: false)
      stream.data(ctx[:opts][:payload], end_stream: true)
    else
      stream.headers(headers, end_stream: true)
    end

    headers = nil
    body = +''
    done = nil

    stream.on(:headers) { |h| headers = h.to_h }
    stream.on(:data) { |c| body << c }
    stream.on(:close) do
      done = true
      return {
        protocol:    'http2',
        status_code: headers && headers[':status'].to_i,
        headers:     headers || {},
        body:        body
      }
    end

    while (data = state[:socket].readpartial(8192))
      state[:http2_client] << data
    end
  ensure
    stream.close unless done
  end

  def protocol
    :http2
  end
end
