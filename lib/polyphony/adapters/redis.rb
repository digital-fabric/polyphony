# frozen_string_literal: true

require_relative '../../polyphony'

require 'redis'
require 'hiredis/reader'

# Polyphony-based Redis driver
class Polyphony::RedisDriver

  # Connects to a Redis server using the given config.
  #
  # @return [TCPSocket, UNIXSocket, SSLSocket] client connectio
  def self.connect(config)
    raise 'unix sockets not supported' if config[:scheme] == 'unix'

    # connection.connect_unix(config[:path], connect_timeout)

    raise 'ssl not supported' if config[:scheme] == 'rediss' || config[:ssl]

    # raise NotImplementedError, "SSL not supported by hiredis driver"

    new(config[:host], config[:port])
    # connection.connect(config[:host], config[:port], connect_timeout)
  end

  # Initializes a Redis client connection.
  #
  # @param host [String] hostname
  # @param port [Integer] port number
  def initialize(host, port)
    @connection = Polyphony::Net.tcp_connect(host, port)
    @reader = ::Hiredis::Reader.new
  end

  # Returns true if connected to server.
  #
  # @return [bool] is connected to server
  def connected?
    @connection && !@connection.closed?
  end

  # Sets a timeout for the connection.
  #
  # @return [void]
  def timeout=(timeout)
    # ignore timeout for now
  end

  # Disconnects from the server.
  #
  # @return [void]
  def disconnect
    @connection.close
    @connection = nil
  end

  # Sends a command to the server.
  #
  # @param command [Array] Redis command
  # @return [void]
  def write(command)
    @connection.write(format_command(command))
  end

  # Formats a command for sending to server.
  #
  # @param args [Array] command
  # @return [String] formatted command
  def format_command(args)
    args = args.flatten
    (+"*#{args.size}\r\n").tap do |s|
      args.each do |a|
        a = a.to_s
        s << "$#{a.bytesize}\r\n#{a}\r\n"
      end
    end
  end

  # Reads from the connection, feeding incoming data to the parser.
  #
  # @return [void]
  def read
    reply = @reader.gets
    return reply if reply

    @connection.read_loop do |data|
      @reader.feed(data)
      reply = @reader.gets
      return reply unless reply == false
    end
  end
end

Redis::Connection.drivers << Polyphony::RedisDriver
