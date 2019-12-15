# frozen_string_literal: true

export_default :Agent

require 'uri'
require 'http/2'

ResourcePool = import '../../core/resource_pool'
HTTP1Adapter = import './http1'
SiteConnectionManager = import './site_connection_manager'

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

  def initialize
    @pools = Hash.new do |h, k|
      h[k] = SiteConnectionManager.new(k)
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
    case response.status_code
    when 301, 302
      redirect(response.headers['Location'], ctx, opts)
    when 200, 204
      response
    else
      raise "Error received from server: #{response.status_code}"
    end
  end

  def redirect(url, ctx, opts)
    url = redirect_url(url, ctx)
    request(url, opts)
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

  def do_request(ctx)
    key = uri_key(ctx[:uri])

    @pools[key].acquire do |adapter|
      adapter.request(ctx)
    end
  end

  def uri_key(uri)
    { scheme: uri.scheme, host: uri.host, port: uri.port }
  end
end
