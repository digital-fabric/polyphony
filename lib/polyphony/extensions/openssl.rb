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
    read_watcher = nil
    write_watcher = nil
    loop do
      case (result = read_nonblock(maxlen, buf, exception: false))
      when :wait_readable then (read_watcher ||= io.read_watcher).await
      when :wait_writable then (write_watcher ||= io.write_watcher).await
      else result
      end
    end
  end

  def flush
    # osync = @sync
    # @sync = true
    # do_write ""
    # return self
    # ensure
    # @sync = osync
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
    read_watcher = nil
    write_watcher = nil
    loop do
      case (result = write_nonblock(buf, exception: false))
      when :wait_readable then (read_watcher ||= io.read_watcher).await
      when :wait_writable then (write_watcher ||= io.write_watcher).await
      else result
      end
    end
  end
end
