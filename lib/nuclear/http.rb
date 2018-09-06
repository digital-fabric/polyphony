# frozen_string_literal: true

export :Server

require 'http/parser'

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

  # Handles a new connection
  # @param socket [Net::Socket] connection
  # @return [void]
  def new_connection(socket)
    parser = Http::Parser.new
    parser.on_message_complete = -> { handle_request(socket, parser) }

    socket.on(:data) do |data|
      parse_incoming_data(socket, parser, data)
    end
  end

  # Parses incoming data
  # @param socket [Net::Socket] connection
  # @param parser [Http::Parser] associated HTTP parser
  # @param data [String] data received from connection
  # @return [void]
  def parse_incoming_data(socket, parser, data)
    parser << data
  rescue StandardError => e
    puts "parsing error: #{e.inspect}"
    socket.close
  end

  # Handles request emitted by parser. The request is passed to the request
  # handler block passed to HTTP::Server.new
  # @param socket [Net::Socket] connection
  # @param parser [Http::Parser] associated HTTP parser
  # @return [void]
  def handle_request(socket, parser)
    @request_handler.(socket, parser)
    parser.keep_alive? ? parser.reset! : socket.close
  end
end
