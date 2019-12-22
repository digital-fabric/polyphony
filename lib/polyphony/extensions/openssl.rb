# frozen_string_literal: true

require 'openssl'

import('./socket')

# Open ssl socket helper methods (to make it compatible with Socket API)
class ::OpenSSL::SSL::SSLSocket
  def dont_linger
    io.dont_linger
  end

  def no_delay
    io.no_delay
  end

  def reuse_addr
    io.reuse_addr
  end

  def sysread(maxlen, buf)
    loop do
      read_watcher = nil
      write_watcher = nil
      result = read_nonblock(maxlen, buf, exception: false)
      if result == :wait_readable
        read_watcher ||= Gyro::IO.new(io, :r)
        read_watcher.await
      elsif result == :wait_writable
        write_watcher ||= Gyro::IO.new(io, :w)
        write_watcher.await
      else
        return result
      end
    end
  end

  def flush
  #   osync = @sync
  #   @sync = true
  #   do_write ""
  #   return self
  # ensure
  #   @sync = osync
  end

  # def do_write(s)
  #   @wbuffer = "" unless defined? @wbuffer
  #   @wbuffer << s
  #   @wbuffer.force_encoding(Encoding::BINARY)
  #   @sync ||= false
  #   if @sync or @wbuffer.size > BLOCK_SIZE
  #     until @wbuffer.empty?
  #       begin
  #         nwrote = syswrite(@wbuffer)
  #       rescue Errno::EAGAIN
  #         retry
  #       end
  #       @wbuffer[0, nwrote] = ""
  #     end
  #   end
  # end

  def syswrite(buf)
    loop do
      read_watcher = nil
      write_watcher = nil
      result = write_nonblock(buf, exception: false)
      if result == :wait_readable
        read_watcher ||= Gyro::IO.new(io, :r)
        read_watcher.await
      elsif result == :wait_writable
        write_watcher ||= Gyro::IO.new(io, :w)
        write_watcher.await
      else
        return result
      end
    end
  end
end
