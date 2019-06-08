# frozen_string_literal: true

export_default :Request

require 'uri'

class Request
  attr_reader :body

  def initialize(conn, parser, body)
    @conn         = conn
    @parser       = parser
    @method       = parser.http_method
    @request_url  = parser.request_url
    @body         = body
  end

  def protocol
    'http/1.1'
  end

  def method
    @method ||= @parser.http_method
  end

  def uri
    @uri ||= URI.parse(@parser.request_url || '')
  end

  def path
    @path ||= uri.path
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

  def headers
    @headers ||= @parser.headers
  end

  EMPTY_HASH = {}

  def respond(chunk, headers = EMPTY_HASH)
    status = headers.delete(':status') || 200
    data = format_head(headers)
    if chunk
      data << "#{chunk.bytesize.to_s(16)}\r\n#{chunk}\r\n0\r\n\r\n"
    end
    @conn << data
  end

  def format_head(headers)
    status = headers[':status'] || 200
    data = +"HTTP/1.1 #{status}\r\nTransfer-Encoding: chunked\r\n"
    headers.each do |k, v|
      next if k =~ /^:/
      if v.is_a?(Array)
        v.each { |o| data << "#{k}: #{o}\r\n" }
      else
        data << "#{k}: #{v}\r\n"
      end
    end
    data << "\r\n"
  end

  def write_head(headers = EMPTY_HASH)
    @conn << format_head(headers)
  end

  def write(chunk)
    data = +"#{chunk.bytesize.to_s(16)}\r\n#{chunk}\r\n"
  end

  def finish
    @conn << "0\r\n\r\n"
  end
end
