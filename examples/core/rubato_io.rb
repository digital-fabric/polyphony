# frozen_string_literal: true

require 'socket'
require 'openssl'
require_relative './rubato'

class IOWrapper
  attr_reader :io

  def initialize(io, opts = {})
    @io = io
    @opts = opts
  end

  def close
    @read_watcher&.stop
    @write_watcher&.stop
    @io.close
  end

  ZERO_LINGER = [0, 0].pack("ii")

  def dont_linger
    @io.setsockopt(Socket::SOL_SOCKET, Socket::SO_LINGER, ZERO_LINGER)
  end

  def set_no_delay
    @io.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
  end

  def reuse_addr
    @io.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, 1)
  end

  def read_watcher
    @read_watcher ||= EV::IO.new(@io, :r)
  end

  def write_watcher
    @write_watcher ||= EV::IO.new(@io, :w)
  end

  NO_EXCEPTION_OPTS = { exception: false }.freeze

  def read(max = 8192)
    proc { read_async(max) }
  end

  def read_async(max)
    loop do
      result = @io.read_nonblock(max, NO_EXCEPTION_OPTS)
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
    proc { write_async(data) }
  end

  def write_async(data)
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
    loop do
      result = @io.connect_nonblock(addr, exception: false)
      case result
      when 0              then return result
      when :wait_writable then write_watcher.await
      else                raise IOError
      end
    end
  ensure
    @write_watcher&.stop
  end

  def connect_ssl_handshake_async
    @io = OpenSSL::SSL::SSLSocket.new(@io, @opts[:secure_context])
    loop do
      result = @io.connect_nonblock(exception: false)
      case result
      when OpenSSL::SSL::SSLSocket  then return true
      when :wait_readable           then read_watcher.await
      when :wait_writable           then write_watcher.await
      else                          
        raise IOError, "Failed SSL handshake: #{result.inspect}"
      end
    end
  ensure
    @read_watcher&.stop
    @write_watcher&.stop
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
    loop do
      result, client_addr = @io.accept_nonblock(exception: false)
      case result
      when Socket         then return result
      when :wait_readable then read_watcher.await
      else                     raise "failed to accept (#{result.inspect})"
      end
    end
  ensure
    @read_watcher&.stop
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
