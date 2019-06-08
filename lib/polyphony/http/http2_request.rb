# frozen_string_literal: true

export_default :Request

require 'uri'

class Request
  attr_reader :headers

  def initialize(stream)
    @stream = stream
  end

  def protocol
    'h2'
  end

  def set_headers(headers)
    @headers = Hash[*headers.flatten]
  end

  def add_body_chunk(chunk)
    if @body
      @body << chunk
    else
      @body = +chunk
    end
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

  def respond(body, headers = EMPTY_HASH)
    headers[':status'] ||= '200'

    @stream.headers(headers, end_stream: false)
    @stream.data(body, end_stream: true)
  end
end
