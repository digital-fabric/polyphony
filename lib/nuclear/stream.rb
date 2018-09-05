# frozen_string_literal: true

export_default :Stream

Reactor =     import('./reactor')
Concurrency = import('./concurrency')

# Implements a duplex stream that can buffer and emit events on sending or
# receiving data
class Stream
  # Initializes a new stream
  def initialize(opts = {})
    @opts = opts
    @callbacks = {}
    @open = true
    if opts[:object_mode]
      @read_buffer = []
      @write_buffer = []
    else
      @read_buffer = +''
      @write_buffer = +''
    end
  end

  # Returns true if stream is open
  # @return [Boolean]
  def open?
    @open
  end

  # Sets a callback for the given kind of event
  # @param kind [Symbol] event kind
  # @param proc [Proc] callback as alternative to passing a block
  # @return [void]
  def on(kind, proc = nil, &block)
    @callbacks[kind] = proc || block
  end

  # Push data into the read buffer
  # @param data [String, any] data to be read
  # @return [void]
  def push(data)
    if data.nil?
      @open = false
      return @events[:close]
    end
    @read_buffer << data
    return if @pending_emit_data
    @pending_emit_data = true
    Reactor.next_tick { emit_data }
  end

  # Emits data in the read buffer to the registered :data callback
  # @return [void]
  def emit_data
    @pending_emit_data = nil
    @callbacks[:data].(@read_buffer)
  end

  # Pushes data into the write buffer
  # @param data [String, any] data to be written
  # @return [void]
  def <<(data)
    @write_buffer << data
  end
end
