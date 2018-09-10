# frozen_string_literal: true

export :Connection

require 'hiredis/reader'

Core  = import('../core')
Net   = import('../net')

Commands = import('./redis/commands')

# Redis connection
class Connection < Net::Socket
  include Commands

  # Initializes connection
  def initialize(opts = {})
    super(nil, opts)
    @opts[:host] ||= '127.0.0.1'
    @opts[:port] ||= 6379
    @opts[:timeout] ||= 5
    @queue = []

    setup_reader
  end

  # Returns true if connected
  # @return [Boolean]
  def connected?
    @socket&.connected?
  end

  # Connects to redis server
  # @return [void]
  def connect
    super(@opts[:host], @opts[:port], @opts)
  end

  # Setups Hiredis reader
  # @return [void]
  def setup_reader
    @reader = ::Hiredis::Reader.new
    on(:data) { |data| process_incoming_data(data) }
  end

  # Processes data received from server
  # @param data [String] data received
  # @return [void]
  def process_incoming_data(data)
    @reader.feed(data)
    loop do
      reply = @reader.gets
      break if reply == false
      handle_reply(reply)
    end
  end

  # Handles reply from server
  # @param reply [Object] reply
  # @return [void]
  def handle_reply(reply)
    _, transform, promise = @queue.shift
    if reply.is_a?(RuntimeError)
      Core.next_tick { promise.error(reply) }
    else
      reply = transform.(reply) if transform
      Core.next_tick { promise.resolve(reply) }
    end
  end

  # Queues a command to be sent to the server, sends it if not busy
  # @return [void]
  def cmd(*args, &result_transform)
    Core.promise do |p|
      @queue << [args, result_transform, p]
      send_command(*args)
    end
  end

  # Sends command to server
  # @return [void]
  def send_command(*args)
    self << format_command(*args)
  end

  # Formats command to be sent to server
  # @return [String] protocol message
  def format_command(*args)
    (+"*#{args.size}\r\n").tap do |s|
      args.each do |a|
        a = a.to_s
        s << "$#{a.bytesize}\r\n#{a}\r\n"
      end
    end
  end
end
