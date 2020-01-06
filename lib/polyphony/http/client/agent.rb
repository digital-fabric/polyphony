# frozen_string_literal: true

export_default :Agent

require 'uri'

ResourcePool = import '../../core/resource_pool'
SiteConnectionManager = import './site_connection_manager'

# Implements an HTTP agent
class Agent
  def self.get(*args, &block)
    default.get(*args, &block)
  end

  def self.post(*args, &block)
    default.post(*args, &block)
  end

  def self.default
    @default ||= new
  end

  def initialize
    @pools = Hash.new do |h, k|
      h[k] = SiteConnectionManager.new(k)
    end
  end

  OPTS_DEFAULT = {}.freeze

  def get(url, opts = OPTS_DEFAULT, &block)
    request(url, opts.merge(method: :GET), &block)
  end

  def post(url, opts = OPTS_DEFAULT, &block)
    request(url, opts.merge(method: :POST), &block)
  end

  def request(url, opts = OPTS_DEFAULT, &block)
    ctx = request_ctx(url, opts)

    response = do_request(ctx, &block)
    case response.status_code
    when 301, 302
      redirect(response.headers['Location'], ctx, opts, &block)
    when 200, 204
      response
    else
      raise "Error received from server: #{response.status_code}"
    end
  end

  def redirect(url, ctx, opts, &block)
    url = redirect_url(url, ctx)
    request(url, opts, &block)
  end

  def redirect_url(url, ctx)
    case url
    when /^http(?:s)?\:\/\//
      url
    when /^\/\/(.+)$/
      ctx[:uri].scheme + url
    when /^\//
      format_uri(url, ctx)
    else
      ctx[:uri] + url
    end
  end

  def format_uri(url, ctx)
    format(
      '%<scheme>s://%<host>s%<url>s',
      scheme: ctx[:uri].scheme,
      host:   ctx[:uri].host,
      url:    url
    )
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

  def do_request(ctx, &block)
    key = uri_key(ctx[:uri])

    @pools[key].acquire do |adapter|
      send_request_and_check_response(adapter, ctx, &block)
    end
  rescue Exception => e
    p e
    puts e.backtrace.join("\n")
  end

  def send_request_and_check_response(adapter, ctx, &block)
    response = adapter.request(ctx)
    case response.status_code
    when 200, 204
      if block
        block.(response)
      else
        # read body
        response.body
      end
    end
    response
  end

  def uri_key(uri)
    { scheme: uri.scheme, host: uri.host, port: uri.port }
  end
end
