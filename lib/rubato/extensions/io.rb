# frozen_string_literal: true

class ::IO
  def read_watcher
    @read_watcher ||= EV::IO.new(self, :r)
  end

  def write_watcher
    @write_watcher ||= EV::IO.new(self, :w)
  end

  def stop_watchers
    @read_watcher&.stop
    @write_watcher&.stop
  end

  NO_EXCEPTION = { exception: false }.freeze

  def read(max = 8192)
    @read_buffer ||= +''
    loop do
      result = read_nonblock(max, @read_buffer, NO_EXCEPTION)
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
      result = write_nonblock(data, NO_EXCEPTION)
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