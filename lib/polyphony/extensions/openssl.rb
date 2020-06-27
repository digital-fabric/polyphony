# frozen_string_literal: true

require 'openssl'

require_relative './socket'

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
      case (result = read_nonblock(maxlen, buf, exception: false))
      when :wait_readable then Thread.current.agent.wait_io(io, false)
      when :wait_writable then Thread.current.agent.wait_io(io, true)
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

  def syswrite(buf)
    loop do
      case (result = write_nonblock(buf, exception: false))
      when :wait_readable then Thread.current.agent.wait_io(io, false)
      when :wait_writable then Thread.current.agent.wait_io(io, true)
      else result
      end
    end
  end
end
