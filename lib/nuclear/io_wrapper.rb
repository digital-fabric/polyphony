# frozen_string_literal: true

export :Wrapper

Core = import('./core')

class Wrapper
  def initialize(io, opts = {})
    @io = io
    @opts = opts
  end

  def close
    @io.close
    @read_watcher&.stop
    @write_watcher&.stop
  end

  def read_watcher
    @read_watcher ||= EV::IO.new(@io, :r, false) { }
  end

  def write_watcher
    @write_watcher ||= EV::IO.new(@io, :w, false) { }
  end

  NO_EXCEPTION_OPTS = { exception: false }.freeze

  def read(max = 8192)
    proc do
      fiber = Fiber.current
      result = @io.read_nonblock(max, NO_EXCEPTION_OPTS)
      case result
      when nil
        close
        raise 'socket closed'
      when :wait_readable
        read_watcher.start do
          @read_watcher.stop
          fiber.resume @io.read_nonblock(max, NO_EXCEPTION_OPTS)
        end
        suspend
      else
        result
      end
    ensure
      @read_watcher&.stop
    end
  end

  def write(data)
    proc { write_async(data) }
  end

  def write_async(data)
    loop do
      result = @io.write_nonblock(data, exception: false)
      case result
      when nil
        close
        raise 'socket closed'
      when :wait_writable
        write_watcher.start do
          @write_watcher.stop
          fiber.resume
        end
        suspend
      else
        if result == data.bytesize
          return result
        else
          data = data[result..-1]
        end
      end
    end
  ensure
    @write_watcher&.stop
  end


end

