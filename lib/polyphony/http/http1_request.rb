# frozen_string_literal: true

export_default :Request

require 'uri'

class Request
  def initialize(conn, parser, body)
    @conn         = conn
    @parser       = parser
    @method       = parser.http_method
    @request_url  = parser.request_url
    @body         = body
  end

  def method
    @method ||= @parser.http_method
  end

  S_EMPTY     = ''

  def path
    @uri ||= URI.parse(@parser.request_url || S_EMPTY)
    @path ||= @uri.path
  end

  S_AMPERSAND = '&'
  S_EQUAL     = '='
  
  def query
    @uri ||= URI.parse(@parser.request_url || S_EMPTY)
    return @query if @query
  
    if (q = @uri.query)
      @query = q.split(S_AMPERSAND).each_with_object({}) do |kv, h|
        k, v = kv.split(S_EQUAL)
        h[k.to_sym] = URI.decode_www_form_component(v)
      end
    else
      @query = {}
    end
  end

  def headers
    @headers ||= @parser.headers
  end

  S_CONTENT_LENGTH  = 'Content-Length'
  S_STATUS          = ':status'
  EMPTY_LINE = "\r\n"

  def respond(body, headers = {})
    status = headers.delete(S_STATUS) || 200
    data = +"HTTP/1.1 #{status}\r\n"
    headers[S_CONTENT_LENGTH] = body.bytesize if body
    headers.each do |k, v|
      if v.is_a?(Array)
        v.each { |vv| data << "#{k}: #{vv}\r\n" }
      else
        data << "#{k}: #{v}\r\n"
      end
    end
    if body
      data << "\r\n#{body}"
    else
      data << EMPTY_LINE
    end

    @conn << data
  end
end
