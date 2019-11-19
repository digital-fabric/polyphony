# frozen_string_literal: true

export_default :HTTP1Adapter

require 'http/parser'

Request = import('./request')
HTTP2 = import('./http2')
Exceptions = import('../../core/exceptions')

# HTTP1 protocol implementation
class HTTP1Adapter
  # Initializes a protocol adapter instance
  def initialize(conn, opts)
    @conn = conn
    @opts = opts
    @parser = HTTP::Parser.new(self)
  end

  def each(&block)
    while (data = @conn.readpartial(8192)) do
      @parser << data
      snooze
      while (request = @requests_head)
        return if upgrade_connection(request.headers, &block)

        @requests_head = request.__next__
        block.call(request)
        return unless request.keep_alive?
      end
    end
  rescue SystemCallError, IOError
    # ignore
  ensure
    # release references to various objects
    @requests_head = @requests_tail = nil
    @parser = nil
    @conn.close
  end

  # Reads a body chunk for the current request. Transfers control to the parse
  # loop, and resumes once the parse_loop has fired the on_body callback
  def get_body_chunk
    @waiting_for_body_chunk = true
    @next_chunk = nil
    while !@requests_tail.complete? && (data = @conn.readpartial(8192)) do
      @parser << data
      return @next_chunk if @next_chunk
      snooze
    end
    nil
  ensure
    @waiting_for_body_chunk = nil
  end

  # Waits for the current request to complete. Transfers control to the parse
  # loop, and resumes once the parse_loop has fired the on_message_complete
  # callback
  def consume_request
    request = @requests_head
    while (data = @conn.readpartial(8192)) do
      @parser << data
      return if request.complete?
      snooze
    end
  end

  def protocol
    version = @parser.http_version
    "HTTP #{version.join('.')}"
  end
  
  def on_headers_complete(headers)
    headers[':path'] = @parser.request_url
    headers[':method'] = @parser.http_method
  
    request = Request.new(headers, self)
    if @requests_head
      @requests_tail.__next__ = request
      @requests_tail = request
    else
      @requests_head = @requests_tail = request
    end
  end
  
  def on_body(chunk)
    if @waiting_for_body_chunk
      @next_chunk = chunk
      @waiting_for_body_chunk = nil
    else
      @requests_tail.buffer_body_chunk(chunk)
    end
  end
  
  def on_message_complete
    @waiting_for_body_chunk = nil
    @requests_tail.complete!(@parser.keep_alive?)
  end

  # Upgrades the connection to a different protocol, if the 'Upgrade' header is
  # given. By default the only supported upgrade protocol is HTTP2. Additional
  # protocols, notably WebSocket, can be specified by passing a hash to the
  # :upgrade option when starting a server:
  #
  #     opts = {
  #       upgrade: {
  #         websocket: Polyphony::Websocket.handler(&method(:ws_handler))
  #       }
  #     }
  #     Polyphony::HTTP::Server.serve('0.0.0.0', 1234, opts) { |req| ... }
  #
  # @param headers [Hash] request headers
  # @return [boolean] truthy if the connection has been upgraded
  def upgrade_connection(headers, &block)
    upgrade_protocol = headers['Upgrade']
    return nil unless upgrade_protocol
    
    upgrade_protocol = upgrade_protocol.downcase.to_sym
    upgrade_handler = @opts[:upgrade] && @opts[:upgrade][upgrade_protocol]
    if upgrade_handler
      upgrade_handler.(@conn, headers)
      return true
    end

    return nil unless upgrade_protocol == :h2c

    # upgrade to HTTP/2
    HTTP2.upgrade_each(@conn, @opts, http2_upgraded_headers(headers), &block)
    true
  end

  # Returns headers for HTTP2 upgrade
  # @param headers [Hash] request headers
  # @return [Hash] headers for HTTP2 upgrade
  def http2_upgraded_headers(headers)
    headers.merge(
      ':scheme'    => 'http',
      ':authority' => headers['Host']
    )
  end

  # response API

  # Sends response including headers and body. Waits for the request to complete
  # if not yet completed. The body is sent using chunked transfer encoding.
  # @param body [String] response body
  # @param headers
  def respond(body, headers)
    consume_request if @parsing
    data = format_headers(headers, body)
    if body
      data << if @parser.http_minor == 0
                body
              else
                "#{body.bytesize.to_s(16)}\r\n#{body}\r\n0\r\n\r\n"
              end
    end
    @conn << data
  end

  DEFAULT_HEADERS_OPTS = {
    empty_response: false,
    consume_request: true
  }.freeze

  # Sends response headers. If empty_response is truthy, the response status
  # code will default to 204, otherwise to 200.
  # @param headers [Hash] response headers
  # @param empty_response [boolean] whether a response body will be sent
  # @return [void]
  def send_headers(headers, opts = DEFAULT_HEADERS_OPTS)
    @conn << format_headers(headers, !opts[:empty_response])
  end

  # Sends a response body chunk. If no headers were sent, default headers are
  # sent using #send_headers. if the done option is true(thy), an empty chunk
  # will be sent to signal response completion to the client.
  # @param chunk [String] response body chunk
  # @param done [boolean] whether the response is completed
  # @return [void]
  def send_body_chunk(chunk, done: false)
    data = +"#{chunk.bytesize.to_s(16)}\r\n#{chunk}\r\n"
    data << "0\r\n\r\n" if done
    @conn << data
  end

  # Finishes the response to the current request. If no headers were sent,
  # default headers are sent using #send_headers.
  # @return [void]
  def finish
    @conn << "0\r\n\r\n"
  end

  private

  # Formats response headers. If empty_response is true(thy), the response
  # status code will default to 204, otherwise to 200.
  # @param headers [Hash] response headers
  # @param empty_response [boolean] whether a response body will be sent
  # @return [String] formatted response headers
  def format_headers(headers, body)
    status = headers[':status'] || (body ? 200 : 204)
    data = headers_first_line(body, status)

    headers.each do |k, v|
      next if k =~ /^:/

      v.is_a?(Array) ?
        v.each { |o| data << "#{k}: #{o}\r\n" } : data << "#{k}: #{v}\r\n"
    end
    data << "\r\n"
  end

  def headers_first_line(body, status)
    if !body
      if status == 204
        +"HTTP/1.1 #{status}\r\n"
      else
        +"HTTP/1.1 #{status}\r\nContent-Length: 0\r\n"
      end
    elsif @parser.http_minor == 0
      +"HTTP/1.0 #{status}\r\nContent-Length: #{body.bytesize}\r\n"
    else
      +"HTTP/1.1 #{status}\r\nTransfer-Encoding: chunked\r\n"
    end
  end
end
