# frozen_string_literal: true

require 'socket'

require_relative './io'
require_relative '../core/thread_pool'

# Socket overrides (eventually rewritten in C)
class ::Socket
  def accept
    Thread.current.backend.accept(self)
  end

  NO_EXCEPTION = { exception: false }.freeze

  def connect(addr)
    addr = Addrinfo.new(addr) if addr.is_a?(String)
    Thread.current.backend.connect(self, addr.ip_address, addr.ip_port)
  end

  def recv(maxlen, flags = 0, outbuf = nil)
    Thread.current.backend.recv(self, buf || +'', maxlen)
    # outbuf ||= +''
    # loop do
    #   result = recv_nonblock(maxlen, flags, outbuf, **NO_EXCEPTION)
    #   case result
    #   when nil then raise IOError
    #   when :wait_readable then Thread.current.backend.wait_io(self, false)
    #   else
    #     return result
    #   end
    # end
  end

  def recv_loop(&block)
    Thread.current.backend.recv_loop(self, &block)
  end

  def recvfrom(maxlen, flags = 0)
    @read_buffer ||= +''
    loop do
      result = recvfrom_nonblock(maxlen, flags, @read_buffer, **NO_EXCEPTION)
      case result
      when nil then raise IOError
      when :wait_readable then Thread.current.backend.wait_io(self, false)
      else
        return result
      end
    end
  end

  def send(mesg, flags = 0)
    Thread.current.backend.send(self, mesg)
  end

  def write(str)
    Thread.current.backend.send(self, str)
  end
  alias_method :<<, :write

  def readpartial(maxlen, str = +'')
    Thread.current.backend.recv(self, str, maxlen)
  end

  ZERO_LINGER = [0, 0].pack('ii').freeze

  def dont_linger
    setsockopt(Socket::SOL_SOCKET, Socket::SO_LINGER, ZERO_LINGER)
  end

  def no_delay
    setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
  end

  def reuse_addr
    setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, 1)
  end

  def reuse_port
    setsockopt(::Socket::SOL_SOCKET, ::Socket::SO_REUSEPORT, 1)
  end

  class << self
    alias_method :orig_getaddrinfo, :getaddrinfo
    def getaddrinfo(*args)
      Polyphony::ThreadPool.process { orig_getaddrinfo(*args) }
    end
  end
end

# Overide stock TCPSocket code by encapsulating a Socket instance
class ::TCPSocket
  NO_EXCEPTION = { exception: false }.freeze

  attr_reader :io

  def initialize(remote_host, remote_port, local_host = nil, local_port = nil)
    @io = Socket.new Socket::AF_INET, Socket::SOCK_STREAM
    if local_host && local_port
      addr = Addrinfo.tcp(local_host, local_port)
      @io.bind(addr)
    end

    return unless remote_host && remote_port

    addr = Addrinfo.tcp(remote_host, remote_port)
    @io.connect(addr)
  end

  alias_method :orig_close, :close
  def close
    @io ? @io.close : orig_close
  end

  alias_method :orig_setsockopt, :setsockopt
  def setsockopt(*args)
    @io ? @io.setsockopt(*args) : orig_setsockopt(*args)
  end

  alias_method :orig_closed?, :closed?
  def closed?
    @io ? @io.closed? : orig_closed?
  end

  def dont_linger
    setsockopt(::Socket::SOL_SOCKET, ::Socket::SO_LINGER, ::Socket::ZERO_LINGER)
  end

  def no_delay
    setsockopt(::Socket::IPPROTO_TCP, ::Socket::TCP_NODELAY, 1)
  end

  def reuse_addr
    setsockopt(::Socket::SOL_SOCKET, ::Socket::SO_REUSEADDR, 1)
  end

  def reuse_port
    setsockopt(::Socket::SOL_SOCKET, ::Socket::SO_REUSEPORT, 1)
  end

  def recv(maxlen, flags = 0, outbuf = nil)
    Thread.current.backend.recv(self, buf || +'', maxlen)
  end

  def recv_loop(&block)
    Thread.current.backend.recv_loop(self, &block)
  end

  def send(mesg, flags = 0)
    Thread.current.backend.send(self, mesg)
  end

  def write(str)
    Thread.current.backend.send(self, str)
  end
  alias_method :<<, :write

  def readpartial(maxlen, str = nil)
    @read_buffer ||= +''
    result = Thread.current.backend.recv(self, @read_buffer, maxlen)
    raise EOFError unless result

    if str
      str << @read_buffer
    else
      str = @read_buffer
    end
    @read_buffer = +''
    str
  end

  def read_nonblock(len, str = nil, exception: true)
    @io.read_nonblock(len, str, exception: exception)
  end

  def write_nonblock(buf, exception: true)
    @io.write_nonblock(buf, exception: exception)
  end
end

# Override stock TCPServer code by encapsulating a Socket instance.
class ::TCPServer
  def initialize(hostname = nil, port = 0)
    @io = Socket.new Socket::AF_INET, Socket::SOCK_STREAM
    @io.bind(Addrinfo.tcp(hostname, port))
    @io.listen(0)
  end

  alias_method :orig_accept, :accept
  def accept
    @io.accept
  end

  def accept_loop(&block)
    Thread.current.backend.accept_loop(@io, &block)
  end

  alias_method :orig_close, :close
  def close
    @io.close
  end
end
