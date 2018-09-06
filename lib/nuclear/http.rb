# frozen_string_literal: true

export :Server

require 'http/parser'
require 'http/2'

Net = import('./net')

# HTTP server implementation
class Server < Net::Server
  # initializes an HTTP server, using the given block as a request handler
  # @param opts [Hash] options
  def initialize(opts = {}, &block)
    super(opts)
    @request_handler = block
    on(:connection, &method(:new_connection))
  end

  # Starts listening, sets ALPN protocols for a secure server
  # @param opts [Hash] listen options
  # @return [void]
  def listen(opts)
    super(opts)
    setup_alpn_protocols if @secure_context
  end

  ALPN_PROTOCOLS = %w{h2 spdy/2 http/1.1}

  # Sets up ALPN protocols negotiated during handshake
  # @return [void]
  def setup_alpn_protocols
    @secure_context.alpn_protocols = ALPN_PROTOCOLS
    @secure_context.alpn_select_cb = proc do |protocols|
      (ALPN_PROTOCOLS & protocols).first
    end))
  end

  H2_PROTOCOL = 'h2'

  # Handles a new connection
  # @param socket [Net::Socket] connection
  # @return [void]
  def new_connection(socket)
    case alpn_protocol(socket)
    when H2_PROTOCOL
      setup_http2_parser(socket)
    else
      setup_http1_parser(socket)
    end
  end

  # returns the ALPN protocol used for the given socket
  # @param socket [Net::Socket] socket
  # @return [String, nil]
  def alpn_protocol(socket)
    socket.secure? && socket.raw_io.alpn_protocol
  end

  # Sets up HTTP 1 parser
  # @param socket [Net::Socket] socket
  # @return [void]
  def setup_http1_parser(socket)
    socket.opts[:can_upgrade] = true
    parser = Http::Parser.new
    parser.on_message_complete = proc do
      handle_http1_request(socket, parser)
      parser.keep_alive? ? parser.reset! : socket.close
    end

    socket.on(:data) do |data|
      parse_http1_incoming_data(socket, parser, data)
    end
  end

  # Parses incoming data for HTTP 1 connection
  # @param socket [Net::Socket] connection
  # @param parser [Http::Parser] associated HTTP parser
  # @param data [String] data received from connection
  # @return [void]
  def parse_http1_incoming_data(socket, parser, data)
    parser << data
  rescue StandardError => e
    puts "parsing error: #{e.inspect}"
    puts e.backtrace.join("\n")
    socket.close
  end

  # Handles HTTP 1 request, upgrading the connection if possible
  # @param socket [Net::Socket] socket
  # @param parser [::HTTP::Parser] HTTP 1 parser
  # @return [void]
  def handle_http1_request(socket, parser)
    return if socket.opts[:can_upgrade] && upgrade_connection(socket, parser)

    socket.opts[:can_upgrade] = false
    handle_request(socket, parser)
  end

  UPGRADE_MESSAGE = [
    'HTTP/1.1 101 Switching Protocols',
    'Connection: Upgrade',
    'Upgrade: h2c',
    '',
    ''
  ].join("\r\n")

  # Upgrades an HTTP 1 connection to HTTP 2 on client request
  # @param socket [Net::Socket] socket
  # @param parser [::HTTP::Parser] HTTP 1 parser
  # @return [Boolean] true if connection was upgraded
  def upgrade_connection(socket, parser)
    # puts "method: #{parser.method.inspect}"
    # puts "request_url: #{parser.request_url.inspect}"
    return false unless parser.headers['Upgrade'] == 'h2c'

    socket << UPGRADE_MESSAGE
    interface = setup_http2_parser(socket)

    settings = parser.headers['HTTP2-Settings']
    request = {
      ':scheme'    => 'http',
      ':method'    => parser.http_method,
      ':authority' => parser.headers['Host'],
      ':path'      => parser.request_url,
    }.merge(parser.headers)
    body = '' # TODO: get body from parser

    interface.upgrade('', request, body)
    true
  end

  # Sets up HTTP 2 parser
  # @param socket [Net::Socket] socket
  # @return [void]
  def setup_http2_parser(socket)
    interface = HTTP2::Server.new
    interface.on(:frame) { |bytes| socket << bytes }
    socket.on(:data) do |data|
      parse_http2_incoming_data(socket, interface, data)
    end
    interface.on(:stream) do |stream|
      handle_http2_stream(socket, stream)
    end
    interface
  end

  # Parses incoming data for HTTP 2 connection
  # @param socket [Net::Socket] connection
  # @param interface [HTTP2::Server] associated HTTP 2 parser
  # @param data [String] data received from connection
  # @return [void]
  def parse_http2_incoming_data(socket, interface, data)
    interface << data
  rescue => e
    puts "error in parse_http2_incoming_data"
    p e
    puts e.backtrace.join("\n")
    socket.close
  end

  # Handles HTTP 2 stream
  # @param socket [Net::Socket] connection
  # @param stream [HTTP2::Stream] HTTP 2 stream
  # @return [void]
  def handle_http2_stream(socket, stream)
    request, buffer = {}, ''
  
    # stream.on(:active) { puts 'client opened new stream' }
    # stream.on(:close)  { puts 'stream closed' }

    stream.on(:headers) do |h|
      request = Hash[*h.flatten]
      # puts "request headers: #{h}"
    end

    stream.on(:data) do |d|
      # puts "payload chunk: <<#{d}>>"
      buffer << d
    end

    stream.on(:half_close) do
      # puts 'client closed its end of the stream'

      # puts "request: #{req.inspect}"

      response = nil


      # if req[':method'] == 'POST'
      #   # puts "Received POST request, payload: #{buffer}"
      #   response = "Hello HTTP 2.0! POST payload: #{buffer}"
      # else
      #   # puts 'Received GET request'
      #   response = 'Hello HTTP 2.0! GET request'
      # end

      response = handle_request(socket, request)

      stream.headers({
        ':status' => '200',
        'content-length' => response.bytesize.to_s,
        'content-type' => 'text/plain',
      }, end_stream: false)

      stream.data(response)
    end
  end

  # Handles request emitted by parser. The request is passed to the request
  # handler block passed to HTTP::Server.new
  # @param socket [Net::Socket] connection
  # @param request [any] request
  # @return [void]
  def handle_request(socket, request)
    @request_handler.(socket, request)
  end
end
