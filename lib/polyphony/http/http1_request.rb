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

  def path
    @uri ||= URI.parse(@parser.request_url || '')
    @path ||= @uri.path
  end

  def query
    @uri ||= URI.parse(@parser.request_url || '')
    return @query if @query
  
    if (q = @uri.query)
      @query = q.split('&').each_with_object({}) do |kv, h|
        k, v = kv.split('=')
        h[k.to_sym] = URI.decode_www_form_component(v)
      end
    else
      @query = {}
    end
  end

  def headers
    @headers ||= @parser.headers
  end

  def respond(body, headers = {})
    status = headers.delete(':status') || 200
    data = +"HTTP/1.1 #{status}\r\n"
    headers['Content-Length'] = body.bytesize if body
    headers.each do |k, v|
      if v.is_a?(Array)
        v.each { |o| data << "#{k}: #{o}\r\n" }
      else
        data << "#{k}: #{v}\r\n"
      end
    end
    data << "\r\n
    data << body if body

    @conn << data
  end
end
