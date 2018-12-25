# frozen_string_literal: true

export_default :Request

require 'uri'

class Request
  def initialize(stream)
    @stream = stream
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

  S_METHOD = ':method'

  def method
    @method ||= @headers[S_METHOD]
  end

  def scheme
    @scheme ||= @headers[':scheme']
  end

  S_EMPTY     = ''

  def path
    @uri ||= URI.parse(@headers[':path'] || S_EMPTY)
    @path ||= @uri.path
  end

  S_AMPERSAND = '&'
  S_EQUAL     = '='
  
  def query
    @uri ||= URI.parse(@headers[':path'] || S_EMPTY)
    return @query if @query
  
    if (q = u.query)
      @query = q.split(S_AMPERSAND).each_with_object({}) do |kv, h|
        k, v = kv.split(S_EQUAL)
        h[k.to_sym] = URI.decode_www_form_component(v)
      end
    else
      @query = {}
    end
  end

  S_CONTENT_LENGTH = 'Content-Length'
  S_STATUS = ':status'
  S_STATUS_200 = '200'
  EMPTY_LINE = "\r\n"

  def respond(body, headers = {})
    headers[S_STATUS] ||= S_STATUS_200

    @stream.headers(headers, end_stream: false)
    @stream.data(body, end_stream: true)
  end
end
