# frozen_string_literal: true

require 'openssl'
require_relative './socket'

# Open ssl socket helper methods (to make it compatible with Socket API)
class ::OpenSSL::SSL::SSLSocket
  alias_method :orig_initialize, :initialize
  def initialize(socket, context = nil)
    socket = socket.respond_to?(:io) ? socket.io || socket : socket
    context ? orig_initialize(socket, context) : orig_initialize(socket)
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

  alias_method :orig_accept, :accept
  def accept
    loop do
      result = accept_nonblock(exception: false)
      case result
      when :wait_readable then Thread.current.backend.wait_io(io, false)
      when :wait_writable then Thread.current.backend.wait_io(io, true)
      else
        return result
      end
    end
  end

  alias_method :orig_sysread, :sysread
  def sysread(maxlen, buf = +'')
    loop do
      case (result = read_nonblock(maxlen, buf, exception: false))
      when :wait_readable then Thread.current.backend.wait_io(io, false)
      when :wait_writable then Thread.current.backend.wait_io(io, true)
      else return result
      end
    end
  end

  alias_method :orig_syswrite, :syswrite
  def syswrite(buf)
    loop do
      case (result = write_nonblock(buf, exception: false))
      when :wait_readable then Thread.current.backend.wait_io(io, false)
      when :wait_writable then Thread.current.backend.wait_io(io, true)
      else
        return result
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

  def readpartial(maxlen, buf = +'')
    result = sysread(maxlen, buf)
    result || (raise EOFError)
  end

  def read_loop
    while (data = sysread(8192))
      yield data
    end
  end
end
