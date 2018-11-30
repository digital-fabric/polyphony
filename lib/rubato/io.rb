# frozen_string_literal: true

export :IOWrapper

require 'socket'
require 'openssl'

import('./core/ext')

class IOWrapper
  attr_reader :io, :opts

  def initialize(io, opts = {})
    @io = io
    @opts = opts
    @read_buffer = +''
  end

  def close
    @read_watcher&.stop
    @write_watcher&.stop
    @io.close
    @read_buffer = nil
  end

  def read_watcher
    @read_watcher ||= EV::IO.new(@io, :r)
  end

  def write_watcher
    @write_watcher ||= EV::IO.new(@io, :w)
  end

  NO_EXCEPTION = { exception: false }.freeze

  def read(max = 8192)
    loop do
      result = @io.read_nonblock(max, @read_buffer, NO_EXCEPTION)
      case result
      when nil            then raise IOError
      when :wait_readable then read_watcher.await
      else                return result
      end
    end
  ensure
    @read_watcher&.stop
  end

  def write(data)
    loop do
      result = @io.write_nonblock(data, exception: false)
      case result
      when nil            then raise IOError
      when :wait_writable then write_watcher.await
      else
        (result == data.bytesize) ? (return result) : (data = data[result..-1])
      end
    end
  ensure
    @write_watcher&.stop
  end
end
