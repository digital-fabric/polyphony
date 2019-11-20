# frozen_string_literal: true

export_default :Agent

require 'uri'
require 'http/parser'
require 'http/2'
require 'json'

ResourcePool = import('../core/resource_pool')

# Response mixin
module ResponseMixin
  def body
    self[:body]
  end

  def json
    @json ||= ::JSON.parse(self[:body])
  end
end

# Implements an HTTP agent
class Agent
  def self.get(*args)
    default.get(*args)
  end

  def self.post(*args)
    default.post(*args)
  end

  def self.default
    @default ||= new
  end

  def initialize(max_conns = 6)
    @pools = Hash.new do |h, k|
      h[k] = ResourcePool.new(limit: max_conns) { {} }
    end
  end

  OPTS_DEFAULT = {}.freeze

  def get(url, opts = OPTS_DEFAULT)
    request(url, opts.merge(method: :GET))
  end

  def post(url, opts = OPTS_DEFAULT)
    request(url, opts.merge(method: :POST))
  end

  def request(url, opts = OPTS_DEFAULT)
    ctx = request_ctx(url, opts)

    response = do_request(ctx)
    case response[:status_code]
    when 301, 302
      redirect(response[:headers]['Location'], ctx, opts)
    when 200, 204
      response.extend(ResponseMixin)
    else
      raise "Error received from server: #{response[:status_code]}"
    end
  end

  def redirect(url, ctx, opts)
    url = case url
          when /^http(?:s)?\:\/\//
            url
          when /^\/\/(.+)$/
            ctx[:uri].scheme + url
          when /^\//
            format(
              '%<scheme>s://%<host>s%<url>s',
              scheme: ctx[:uri].scheme,
              host:   ctx[:uri].host,
              url:    url
            )
          else
            ctx[:uri] + url
          end

    request(url, opts)
  end

  def request_ctx(url, opts)
    {
      method: opts[:method] || :GET,
      uri:    url_to_uri(url, opts),
      opts:   opts,
      retry:  0
    }
  end

  def url_to_uri(url, opts)
    uri = URI(url)
    if opts[:query]
      query = opts[:query].map { |k, v| "#{k}=#{v}" }.join('&')
      if uri.query
        v.query = "#{uri.query}&#{query}"
      else
        uri.query = query
      end
    end
    uri
  end

  def do_request(ctx)
    key = uri_key(ctx[:uri])
    @pools[key].acquire do |state|
      cancel_after(10) do
        state[:socket] ||= connect(key)
        state[:protocol_method] ||= protocol_method(state[:socket], ctx)
        send(state[:protocol_method], state, ctx)
      rescue Exception => e
        state[:socket]&.close
        state.clear

        raise e unless ctx[:retry] < 3

        ctx[:retry] += 1
        do_request(ctx)
      end
    end
  end

  def protocol_method(socket, _ctx)
    if socket.is_a?(::OpenSSL::SSL::SSLSocket) && (socket.alpn_protocol == 'h2')
      :do_http2
    else
      :do_http1
    end
  end

  def do_http1(state, ctx)
    done = false
    body = +''
    parser = HTTP::Parser.new
    parser.on_message_complete = proc { done = true }
    parser.on_body = proc { |data| body << data }
    request = format_http1_request(ctx)

    state[:socket] << request
    parser << state[:socket].readpartial(8192) until done

    {
      protocol:    'http1.1',
      status_code: parser.status_code,
      headers:     parser.headers,
      body:        body
    }
  end

  def do_http2(state, ctx)
    unless state[:http2_client]
      socket = state[:socket]
      client = HTTP2::Client.new
      client.on(:frame) { |bytes| socket << bytes }
      state[:http2_client] = client
    end

    stream = state[:http2_client].new_stream # allocate new stream

    headers = {
      ':method'    => ctx[:method].to_s,
      ':scheme'    => ctx[:uri].scheme,
      ':authority' => [ctx[:uri].host, ctx[:uri].port].join(':'),
      ':path'      => ctx[:uri].request_uri
    }
    headers.merge!(ctx[:opts][:headers]) if ctx[:opts][:headers]
    puts "* proxy request headers: #{headers.inspect}"

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

  HTTP1_REQUEST = <<~HTTP.gsub("\n", "\r\n")
    %<method>s %<request>s HTTP/1.1
    Host: %<host>s
    %<headers>s

  HTTP

  def format_http1_request(ctx)
    headers = format_headers(ctx)
    puts "* proxy request headers: #{headers.inspect}"

    format(
      HTTP1_REQUEST,
      method:  ctx[:method],
      request: ctx[:uri].request_uri,
      host:    ctx[:uri].host,
      headers: headers
    )
  end

  def format_headers(headers)
    return nil unless ctx[:opts][:headers]

    headers.map { |k, v| "#{k}: #{v}\r\n" }.join
  end

  def uri_key(uri)
    {
      scheme: uri.scheme,
      host:   uri.host,
      port:   uri.port
    }
  end

  SECURE_OPTS = { secure: true, alpn_protocols: ['h2', 'http/1.1'] }.freeze

  def connect(key)
    case key[:scheme]
    when 'http'
      Polyphony::Net.tcp_connect(key[:host], key[:port])
    when 'https'
      Polyphony::Net.tcp_connect(key[:host], key[:port], SECURE_OPTS)
    else
      raise "Invalid scheme #{key[:scheme].inspect}"
    end
  end
end
