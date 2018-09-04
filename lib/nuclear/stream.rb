# frozen_string_literal: true

export_default :Stream

Reactor =     import('./reactor')
Concurrency = import('./concurrency')

class Stream
  def initialize(opts = {})
    @opts = opts
    @callbacks = {}
    @open = true
    if opts[:object_mode]
      @read_buffer = []
      @write_buffer = []
    else
      @read_buffer = (+'')
      @write_buffer = (+'')
    end
  end

  def eof?
    !@open
  end

  def on(kind, proc = nil, &block)
    @callbacks[kind] = proc || block
  end

  def push(data)
    if data.nil?
      @open = false
      return @events[:close]
    end

    @read_buffer << data
    unless @pending_emit_data
      @pending_emit_data = true
      Reactor.next_tick { emit_data }
    end
  end

  def emit_data
    @pending_emit_data = nil
    @callbacks[:data].(@read_buffer)
  end

  def <<(data)
    @write_buffer << data
  end
end
