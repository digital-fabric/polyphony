# frozen_string_literal: true

export  :SocketWrapper,
        :tcp_connect,
        :tcp_listen

require 'socket'
require 'openssl'

RubatoIO = import('./io')

def tcp_connect(host, port, opts = {})
  proc do
    socket = ::Socket.new(:INET, :STREAM)
    SocketWrapper.new(socket, opts).tap do |o|
      await o.connect(host, port)
    end
  end
end

def tcp_listen(host = '0.0.0.0', port = nil, opts = {})
  host ||= '0.0.0.0'
  raise "Port number not specified" unless port
  proc do
    socket = ::Socket.new(:INET, :STREAM)
    SocketWrapper.new(socket, opts).tap do |server|
      await server.bind(host, port)
      await server.listen
    end
  end
end

class SocketWrapper < RubatoIO::IOWrapper
  def initialize(io, opts = {})
    super

    reuse_addr   if opts[:reuse_addr]
    dont_linger  if opts[:dont_linger]

    if @opts[:secure_context] && !@opts[:secure]
      @opts[:secure] = true
    elsif @opts[:secure] && !@opts[:secure_context]
      @opts[:secure_context] = OpenSSL::SSL::SSLContext.new
      @opts[:secure_context].set_params(verify_mode: OpenSSL::SSL::VERIFY_PEER)
    end
  end

  ZERO_LINGER = [0, 0].pack("ii")

  def dont_linger
    @io.setsockopt(Socket::SOL_SOCKET, Socket::SO_LINGER, ZERO_LINGER)
  end

  def no_delay
    @io.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
  end

  def reuse_addr
    @io.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, 1)
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
        SocketWrapper.new(socket, accept_opts)
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

  def accept_opts
    @accept_opts ||= @opts.merge(reuse_addr: nil, dont_linger: nil)
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
