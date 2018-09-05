# frozen_string_literal: true

export :Server

require 'http/parser'

Net = import('./net')

class Server < Net::Server
  def initialize(opts = {}, &block)
    super(opts)

    @request_handler = block
    on(:connection, &method(:new_connection))
  end

  def new_connection(socket)
    parser = Http::Parser.new
    socket.on(:data) do |data|
      parse_incoming_data(socket, parser, data)
    end
    parser.on_message_complete = -> { handle_request(socket, parser) }
  end

  def parse_incoming_data(socket, parser, data)
    parser << data
  rescue StandardError => e
    puts "parsing error: #{e.inspect}"
    socket.close
  end

  def handle_request(socket, parser)
    @request_handler.(socket, parser)
    parser.keep_alive? ? parser.reset! : socket.close
  end
end
