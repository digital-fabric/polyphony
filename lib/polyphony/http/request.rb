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

  def query_string
    @query_string ||= uri.query
  end

  def query
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

  def each_chunk
    while (chunk = @adapter.get_body_chunk)
      yield chunk
    end
  end

  def read
    buf = +''
    while (chunk = @adapter.get_body_chunk)
      buf << chunk
    end
    buf
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