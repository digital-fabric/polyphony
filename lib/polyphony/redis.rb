# frozen_string_literal: true

require_relative '../polyphony'

require "redis"
require "hiredis/reader"

class Driver
  def self.connect(config)
    if config[:scheme] == "unix"
      raise "unix sockets not supported"
      # connection.connect_unix(config[:path], connect_timeout)
    elsif config[:scheme] == "rediss" || config[:ssl]
      raise "ssl not supported"
      # raise NotImplementedError, "SSL not supported by hiredis driver"
    else
      new(config[:host], config[:port])
      # connection.connect(config[:host], config[:port], connect_timeout)
    end
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
    
    while (data = @connection.readpartial(8192))
      @reader.feed(data)
      reply = @reader.gets
      return reply if reply
    end
  end
end

Redis::Connection.drivers << Driver