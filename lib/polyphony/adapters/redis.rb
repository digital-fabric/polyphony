# frozen_string_literal: true

require_relative '../../polyphony'

require 'redis'
require 'hiredis/reader'

# Polyphony-based Redis driver
class Polyphony::RedisDriver
  def self.connect(config)
    raise 'unix sockets not supported' if config[:scheme] == 'unix'

    # connection.connect_unix(config[:path], connect_timeout)

    raise 'ssl not supported' if config[:scheme] == 'rediss' || config[:ssl]

    # raise NotImplementedError, "SSL not supported by hiredis driver"

    new(config[:host], config[:port])
    # connection.connect(config[:host], config[:port], connect_timeout)
  end

  def initialize(host, port)
    @connection = Polyphony::Net.tcp_connect(host, port)
    @reader = ::Hiredis::Reader.new
  end

  def connected?
    @connection && !@connection.closed?
  end

  def timeout=(timeout)
    # ignore timeout for now
  end

  def disconnect
    @connection.close
    @connection = nil
  end

  def write(command)
    @connection.write(format_command(command))
  end

  def format_command(args)
    args = args.flatten
    (+"*#{args.size}\r\n").tap do |s|
      args.each do |a|
        a = a.to_s
        s << "$#{a.bytesize}\r\n#{a}\r\n"
      end
    end
  end

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
