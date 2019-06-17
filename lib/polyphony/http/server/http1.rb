# frozen_string_literal: true

export_default :HTTP1Adapter

require 'http/parser'

Request = import('./request')
HTTP2 = import('./http2')

# HTTP1 protocol implementation
class HTTP1Adapter
  # Initializes a protocol adapter instance
  def initialize(conn, opts)
    @conn = conn
    @opts = opts
    @parser = HTTP::Parser.new(self)
    @parse_fiber = Fiber.new { parse_loop }
  end

  # Parses incoming data, potentially firing parser callbacks. This loop runs on
  # a separate fiber and is resumed only when the handler (client) loop asks for
  # headers, or the request body, or waits for the request to be completed. The
  # control flow is as follows (arrows represent control transfer between
  # fibers):
  #
  #       handler               parse_loop
  #       get_headers     -->   ...
  #                             @parser << @conn.readpartial(8192)
  #       ...             <--   on_headers
  #
  #       get_body        -->   ...
  #       ...             <--   on_body
  #       
  #       consume_request -->   ...
  #                             @parser << @conn.readpartial(8192)
  #       ...             <--   on_message_complete
  #
  def parse_loop
    while (data = @conn.readpartial(8192))
      break unless data
      @parser << data
      snooze
    end
    @calling_fiber.transfer nil
  rescue SystemCallError, IOError => error
    # ignore IO/system call errors
    @calling_fiber.transfer nil
  rescue Exception => error
    # an error return value will be raised by the receiving fiber
    @calling_fiber.transfer error
  end

  # request API

  # Iterates over incoming requests. Requests are yielded once all headers have
  # been received. It is left to the application to read the request body or
  # diesregard it.
  def each(&block)
    can_upgrade = true
    while @parse_fiber.alive? && (headers = get_headers)
      if can_upgrade
        # The connection can be upgraded only on the first request
        return if upgrade_connection(headers, &block)
        can_upgrade = false
      end

      @headers_sent = nil
      block.(Request.new(headers, self))

      if @parser.keep_alive?
        @parsing = false
      else
        break
      end
    end
  ensure
    @conn.close rescue nil
  end

  # Reads headers for the next request. Transfers control to the parse loop,
  # and resumes once the parse_loop has fired the on_headers callback
  def get_headers
    @parsing = true
    @calling_fiber = Fiber.current
    @parse_fiber.safe_transfer
  end

  # Reads a body chunk for the current request. Transfers control to the parse
  # loop, and resumes once the parse_loop has fired the on_body callback
  def get_body_chunk
    @calling_fiber = Fiber.current
    @read_body = true
    @parse_fiber.safe_transfer
  end

  # Waits for the current request to complete. Transfers control to the parse
  # loop, and resumes once the parse_loop has fired the on_message_complete
  # callback
  def consume_request
    return unless @parsing

    @calling_fiber = Fiber.current
    @read_body = false
    @parse_fiber.safe_transfer while @parsing
  end

  def protocol
    version = @parser.http_version
    "HTTP #{version.join('.')}"
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

    if @opts[:upgrade] && @opts[:upgrade][upgrade_protocol.to_sym]
      @opts[:upgrade][upgrade_protocol.to_sym].(@conn, headers)
      return true
    end
  
    return nil unless upgrade_protocol == 'h2c'
    
    # upgrade to HTTP/2
    HTTP2.upgrade_each(@conn, @opts, http2_upgraded_headers(headers), &block)
    true
  end
  
  # Returns headers for HTTP2 upgrade
  # @param headers [Hash] request headers
  # @return [Hash] headers for HTTP2 upgrade
  def http2_upgraded_headers(headers)
    headers.merge(
      ':scheme'     => 'http',
      ':authority'  => headers['Host'],
    )
  end
    
  # HTTP parser callbacks, called in the context of @parse_fiber

  # Resumes client fiber on receipt of all headers
  # @param headers [Hash] request headers
  # @return [void]
  def on_headers_complete(headers)
    headers[':path'] = @parser.request_url
    headers[':method'] = @parser.http_method
    @calling_fiber.transfer(headers)
  end

  # Resumes client fiber on receipt of body chunk
  # @param chunk [String] body chunk
  # @return [void]
  def on_body(chunk)
    @calling_fiber.transfer(chunk) if @read_body
  end

  # Resumes client fiber on request completion
  # @return [void]
  def on_message_complete
    @parsing = false
    @calling_fiber.transfer nil
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
      if @parser.http_minor == 0
        data << body
      else
        data << "#{body.bytesize.to_s(16)}\r\n#{body}\r\n0\r\n\r\n"
      end
    end
    @conn << data
    @headers_sent = true
  end

  DEFAULT_HEADERS_OPTS = {
    empty_response: false,
    consume_request: true
  }

  # Sends response headers. Waits for the request to complete if not yet
  # completed. If empty_response is true(thy), the response status code will
  # default to 204, otherwise to 200.
  # @param headers [Hash] response headers
  # @param empty_response [boolean] whether a response body will be sent
  # @return [void]
  def send_headers(headers, opts = DEFAULT_HEADERS_OPTS)
    return if @headers_sent

    consume_request if @parsing && opts[:consume_request]
    @conn << format_headers(headers, !opts[:empty_response])
    @headers_sent = true
  end

  # Sends a response body chunk. If no headers were sent, default headers are
  # sent using #send_headers. if the done option is true(thy), an empty chunk
  # will be sent to signal response completion to the client.
  # @param chunk [String] response body chunk
  # @param done [boolean] whether the response is completed
  # @return [void]
  def send_body_chunk(chunk, done: false)
    send_headers({}) unless @headers_sent

    data = +"#{chunk.bytesize.to_s(16)}\r\n#{chunk}\r\n"
    data << "0\r\n\r\n" if done
    @conn << data
  end
  
  # Finishes the response to the current request. If no headers were sent,
  # default headers are sent using #send_headers.
  # @return [void]
  def finish
    send_headers({}, true) unless @headers_sent

    @conn << "0\r\n\r\n" if @body_sent
  end

  private

  # Formats response headers. If empty_response is true(thy), the response
  # status code will default to 204, otherwise to 200.
  # @param headers [Hash] response headers
  # @param empty_response [boolean] whether a response body will be sent
  # @return [String] formatted response headers
  def format_headers(headers, body)
    status = headers[':status'] || (body ? 200 : 204)
    data = if !body
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

    headers.each do |k, v|
      next if k =~ /^:/
      v.is_a?(Array) ?
        v.each { |o| data << "#{k}: #{o}\r\n" } : data << "#{k}: #{v}\r\n"
    end
    data << "\r\n"
  end
end