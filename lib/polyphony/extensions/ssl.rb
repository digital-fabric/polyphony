# frozen_string_literal: true

require 'openssl'

import('./socket')

class ::OpenSSL::SSL::SSLSocket
  def accept
    loop do
      result = accept_nonblock(::IO::NO_EXCEPTION)
      case result
      when :wait_readable then io.read_watcher.await
      when :wait_writable then io.write_watcher.await
      else                     return true
      end
    end
  ensure
    io.stop_watchers
  end

  def connect
    loop do
      result = connect_nonblock(::IO::NO_EXCEPTION)
      case result
      when :wait_readable then io.read_watcher.await
      when :wait_writable then io.write_watcher.await
      else                     return true
      end
    end
  ensure
    io.stop_watchers
  end

  def read(max = 8192)
    @read_buffer ||= +''
    loop do
      result = read_nonblock(max, @read_buffer, ::IO::NO_EXCEPTION)
      case result
      when nil            then raise ::IOError
      when :wait_readable then io.read_watcher.await
      else                return result
      end
    end
  ensure
    io.stop_watchers
  end

  def write(data)
    loop do
      result = write_nonblock(data, ::IO::NO_EXCEPTION)
      case result
      when nil            then raise ::IOError
      when :wait_writable then io.write_watcher.await
      else
        (result == data.bytesize) ? (return result) : (data = data[result..-1])
      end
    end
  ensure
    io.stop_watchers
  end

  def dont_linger
    io.dont_linger
  end

  def no_delay
    io.no_delay
  end

  def reuse_addr
    io.reuse_addr
  end
end