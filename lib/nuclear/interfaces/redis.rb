# frozen_string_literal: true

require 'hiredis/reader'
export :Connection

Net =         import('../net')
Concurrency = import('../concurrency')
Commands =    import('./redis/commands')

class Connection < Net::Socket
  include Commands

  def initialize(opts = {})
    super(nil, opts)
    @opts[:host] ||= '127.0.0.1'
    @opts[:port] ||= 6379
    @opts[:timeout] ||= 5
    @queue = []

    setup_reader
  end

  def method_missing(m, *args)
    cmd(m, *args)
  end

  def connected?
    @socket&.connected?
  end

  def connect
    super(@opts[:host], @opts[:port], @opts)
  end

  def setup_reader
    @reader = ::Hiredis::Reader.new
    on(:data) { |data| process_incoming_data(data) }
  end

  def process_incoming_data(data)
    @reader.feed(data)
    loop do
      reply = @reader.gets
      break if reply == false
      handle_reply(reply)
    end
  end

  def handle_reply(reply)
    args, transform, promise = @queue.shift
    if reply.is_a?(RuntimeError)
      Reactor.next_tick { promise.error(reply) }
    else
      reply = transform.(reply) if transform
      Reactor.next_tick { promise.resolve(reply) }
    end
  end

  def cmd(*args, &result_transform)
    Concurrency.promise do |p|
      @queue << [args, result_transform, p]
      send_command(*args)
    end
  end

  def send_command(*args)
    self << format_command(*args)
  end

  def format_command(*args)
    (+"*#{args.size}\r\n").tap do |s|
      args.each do |a|
        a = a.to_s
        s << "$#{a.bytesize}\r\n#{a}\r\n"
      end
    end
  end
end

