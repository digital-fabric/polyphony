# frozen_string_literal: true

export :IOWrapper, :SocketWrapper

require 'socket'
require 'openssl'

Core = import('./core')

class ::EV::IO
  def await!(fiber)
    start do
      stop
      fiber.resume
    end
    suspend
  end
end

class IOWrapper
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
    proc { read_async(max) }
  end

  def read_async(max)
    fiber = Fiber.current
    loop do
      result = @io.read_nonblock(max, NO_EXCEPTION_OPTS)
      case result
      when nil
        close
      when :wait_readable
        read_watcher.await!(fiber)
      else
        return result
      end
    end
  ensure
    @read_watcher&.stop
  end

  def write(data)
    proc { write_async(data) }
  end

  def write_async(data)
    fiber = Fiber.current
    loop do
      result = @io.write_nonblock(data, exception: false)
      case result
      when nil
        close
        raise 'socket closed'
      when :wait_writable
        write_watcher.await!(fiber)
      else
        (result == data.bytesize) ? (return result) : (data = data[result..-1])
      end
    end
  ensure
    @write_watcher&.stop
  end
end

class SocketWrapper < IOWrapper
  def initialize(io, opts = {})
    super
    if @opts[:secure_context] && !@opts[:secure]
      @opts[:secure] = true
    elsif @opts[:secure] && !@opts[:secure_context]
      @opts[:secure_context] = OpenSSL::SSL::SSLContext.new
      @opts[:secure_context].set_params(verify_mode: OpenSSL::SSL::VERIFY_PEER)
    end
  end

  def connect(host, port)
    proc do
      connect_async(host, port)
      connect_ssl_handshake_async if @opts[:secure]
    end
  end

  def connect_async(host, port)
    addr = ::Socket.sockaddr_in(port, host)
    fiber = Fiber.current
    loop do
      result = @io.connect_nonblock(addr, exception: false)
      case result
      when 0
        return result
      when :wait_writable
        write_watcher.await!(fiber)
      else
        close
        raise 'failed to connect'
      end
    end
  end

  def connect_ssl_handshake_async
    @io = OpenSSL::SSL::SSLSocket.new(@io, @opts[:secure_context])
    fiber = Fiber.current
    loop do
      result = @io.connect_nonblock(exception: false)
      case result
      when OpenSSL::SSL::SSLSocket
        return true
      when :wait_readable
        read_watcher.await!(fiber)
      when :wait_writable
        write_watcher.await!(fiber)
      else
        raise "Failed SSL handshake: #{result.inspect}"
      end
    end
  end

  def accept
    proc do
      socket = accept_async
      if @opts[:secure]
        accept_ssl_handshake_async(socket)
      else
        SocketWrapper.new(socket, @opts)
      end
    end
  end

  def accept_async
    fiber = Fiber.current
    loop do
      result, client_addr = @io.accept_nonblock(exception: false)
      case result
      when Socket
        return result
      when :wait_readable
        read_watcher.await!(fiber)
      else
        close
        raise "failed to accept (#{result.inspect})"
      end
    end
  rescue Exception => e
    close
    raise e
  end

  def bind(host, port)
    proc {
      addr = ::Socket.sockaddr_in(port, host)
      @io.bind(addr)
    }
  end

  def listen(backlog = 0)
    proc {
      @io.listen(backlog)
    }
  end
end