# frozen_string_literal: true

export_default :HTTP1Adapter

require 'http/parser'

Response = import './response'

# HTTP 1 adapter
class HTTP1Adapter
  def initialize(socket)
    @socket = socket
    @parser = HTTP::Parser.new(self)
  end

  def on_headers_complete(headers)
    @headers = headers
  end

  def on_body(chunk)
    if @waiting_for_chunk
      @buffered_chunks ||= []
      @buffered_chunks << chunk
    elsif @buffered_body
      @buffered_body << chunk
    else
      @buffered_body = +chunk
    end
  end

  def on_message_complete
    @done = true
  end

  def request(ctx)
    # consume previous response if not finished
    consume_response if @done == false

    @socket << format_http1_request(ctx)

    @buffered_body = nil
    @done = false

    read_headers
    Response.new(self, @parser.status_code, @headers)
  end

  def read_headers
    @headers = nil
    while !@headers && (data = @socket.readpartial(8192))
      @parser << data
    end

    raise 'Socket closed by host' unless @headers
  end

  def body
    @waiting_for_chunk = nil
    consume_response
    @buffered_body
  end

  def each_chunk(&block)
    if (body = @buffered_body)
      @buffered_body = nil
      @waiting_for_chunk = true
      block.(body)
    end
    while !@done && (data = @socket.readpartial(8192))
      @parser << data
    end
    raise 'Socket closed by host' unless @done

    @buffered_chunks.each(&block)
  end

  def next_body_chunk
    return nil if @done
    if @buffered_chunks && !@buffered_chunks.empty?
      return @buffered_chunks.shift
    end

    read_next_body_chunk
  end

  def read_next_body_chunk
    @waiting_for_chunk = true
    while !@done && (data = @socket.readpartial(8192))
      @parser << data
      break unless @buffered_chunks.empty?
    end
    @buffered_chunks.shift
  end

  def consume_response
    while !@done && (data = @socket.readpartial(8192))
      @parser << data
    end

    raise 'Socket closed by host' unless @done
  end

  HTTP1_REQUEST = <<~HTTP.gsub("\n", "\r\n")
    %<method>s %<request>s HTTP/1.1
    Host: %<host>s
    %<headers>s

  HTTP

  def format_http1_request(ctx)
    headers = format_headers(ctx)

    format(
      HTTP1_REQUEST,
      method:  ctx[:method],
      request: ctx[:uri].request_uri,
      host:    ctx[:uri].host,
      headers: headers
    )
  end

  def format_headers(headers)
    headers.map { |k, v| "#{k}: #{v}\r\n" }.join
  end

  def protocol
    :http1
  end
end
