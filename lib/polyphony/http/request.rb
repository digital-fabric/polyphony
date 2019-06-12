# frozen_string_literal: true

export_default :Request

require 'uri'

class Request
  attr_reader :headers, :adapter

  def initialize(headers, adapter)
    @headers  = headers
    @adapter  = adapter
  end

  def protocol
    @adapter.protocol
  end

  def method
    @method ||= @headers[':method']
  end

  def scheme
    @scheme ||= @headers[':scheme']
  end

  def uri
    @uri ||= URI.parse(@headers[':path'] || '')
  end

  def path
    @path ||= uri.path
  end

  def query
    @uri ||= URI.parse(@headers[':path'] || '')
    return @query if @query
  
    if (q = uri.query)
      @query = q.split('&').each_with_object({}) do |kv, h|
        k, v = kv.split('=')
        h[k.to_sym] = URI.decode_www_form_component(v)
      end
    else
      @query = {}
    end
  end

  EMPTY_HASH = {}

  def respond(chunk, headers = EMPTY_HASH)
    @adapter.respond(chunk, headers)
  end

  def send_headers(headers = EMPTY_HASH, empty_response = false)
    @adapter.send_headers(headers, empty_response)
  end

  def send_body_chunk(body, done: false)
    @adapter.send_body_chunk(body, done: done)
  end

  def finish
    @adapter.finish
  end
end
