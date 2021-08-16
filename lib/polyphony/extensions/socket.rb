# frozen_string_literal: true

require 'socket'

require_relative './io'
require_relative '../core/thread_pool'

class BasicSocket
  def __parser_read_method__
    :backend_recv
  end
end

# Socket overrides (eventually rewritten in C)
class ::Socket
  def accept
    Polyphony.backend_accept(self, TCPSocket)
  end

  def accept_loop(&block)
    Polyphony.backend_accept_loop(self, TCPSocket, &block)
  end

  NO_EXCEPTION = { exception: false }.freeze

  def connect(addr)
    addr = Addrinfo.new(addr) if addr.is_a?(String)
    Polyphony.backend_connect(self, addr.ip_address, addr.ip_port)
  end

  alias_method :orig_read, :read
  def read(maxlen = nil, buf = nil, buf_pos = 0)
    return Polyphony.backend_recv(self, buf, maxlen, buf_pos) if buf
    return Polyphony.backend_recv(self, buf || +'', maxlen, 0) if maxlen
    
    buf = +''
    len = buf.bytesize
    while true
      Polyphony.backend_recv(self, buf, maxlen || 4096, -1)
      new_len = buf.bytesize
      break if new_len == len

      len = new_len
    end
    buf
  end

  def recv(maxlen, flags = 0, outbuf = nil)
    Polyphony.backend_recv(self, outbuf || +'', maxlen, 0)
  end

  def recv_loop(maxlen = 8192, &block)
    Polyphony.backend_recv_loop(self, maxlen, &block)
  end
  alias_method :read_loop, :recv_loop

  def feed_loop(receiver, method = :call, &block)
    Polyphony.backend_recv_feed_loop(self, receiver, method, &block)
  end

  def recvfrom(maxlen, flags = 0)
    buf = +''
    while true
      result = recvfrom_nonblock(maxlen, flags, buf, **NO_EXCEPTION)
      case result
      when nil then raise IOError
      when :wait_readable then Polyphony.backend_wait_io(self, false)
      else
        return result
      end
    end
  end

  # def send(mesg, flags)
  #   Polyphony.backend_send(self, mesg, flags)
  # end

  # def write(*args)
  #   Polyphony.backend_sendv(self, args, 0)
  # end

  # def <<(mesg)
  #   Polyphony.backend_send(self, mesg, 0)
  # end

  def readpartial(maxlen, str = +'', buffer_pos = 0, raise_on_eof = true)
    result = Polyphony.backend_recv(self, str, maxlen, buffer_pos)
    raise EOFError if !result && raise_on_eof
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

  alias_method :orig_read, :read
  def read(maxlen = nil, buf = nil, buf_pos = 0)
    return Polyphony.backend_recv(self, buf, maxlen, buf_pos) if buf
    return Polyphony.backend_recv(self, buf || +'', maxlen, 0) if maxlen
    
    buf = +''
    len = buf.bytesize
    while true
      Polyphony.backend_recv(self, buf, maxlen || 4096, -1)
      new_len = buf.bytesize
      break if new_len == len

      len = new_len
    end
    buf
  end

  def recv(maxlen, flags = 0, outbuf = nil)
    Polyphony.backend_recv(self, outbuf || +'', maxlen, 0)
  end

  def recv_loop(maxlen = 8192, &block)
    Polyphony.backend_recv_loop(self, maxlen, &block)
  end
  alias_method :read_loop, :recv_loop

  def feed_loop(receiver, method = :call, &block)
    Polyphony.backend_recv_feed_loop(self, receiver, method, &block)
  end

  # def send(mesg, flags)
  #   Polyphony.backend_send(self, mesg, flags)
  # end

  # def write(*args)
  #   Polyphony.backend_sendv(self, args, 0)
  # end

  # def <<(mesg)
  #   Polyphony.backend_send(self, mesg, 0)
  # end

  def readpartial(maxlen, str = +'', buffer_pos = 0, raise_on_eof)
    result = Polyphony.backend_recv(self, str, maxlen, buffer_pos)
    raise EOFError if !result && raise_on_eof
    result
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
    Polyphony.backend_accept(@io, TCPSocket)
    # @io.accept
  end

  def accept_loop(&block)
    Polyphony.backend_accept_loop(@io, TCPSocket, &block)
  end

  alias_method :orig_close, :close
  def close
    @io.close
  end
end

class ::UNIXServer
  alias_method :orig_accept, :accept
 def accept
    Polyphony.backend_accept(self, UNIXSocket)
  end

  def accept_loop(&block)
    Polyphony.backend_accept_loop(self, UNIXSocket, &block)
  end
end

class ::UNIXSocket
  alias_method :orig_read, :read
  def read(maxlen = nil, buf = nil, buf_pos = 0)
    return Polyphony.backend_recv(self, buf, maxlen, buf_pos) if buf
    return Polyphony.backend_recv(self, buf || +'', maxlen, 0) if maxlen
    
    buf = +''
    len = buf.bytesize
    while true
      Polyphony.backend_recv(self, buf, maxlen || 4096, -1)
      new_len = buf.bytesize
      break if new_len == len

      len = new_len
    end
    buf
  end

  def recv(maxlen, flags = 0, outbuf = nil)
    Polyphony.backend_recv(self, outbuf || +'', maxlen, 0)
  end

  def recv_loop(maxlen = 8192, &block)
    Polyphony.backend_recv_loop(self, maxlen, &block)
  end
  alias_method :read_loop, :recv_loop

  def feed_loop(receiver, method = :call, &block)
    Polyphony.backend_recv_feed_loop(self, receiver, method, &block)
  end

  def send(mesg, flags)
    Polyphony.backend_send(self, mesg, flags)
  end

  def write(*args)
    Polyphony.backend_sendv(self, args, 0)
  end

  def <<(mesg)
    Polyphony.backend_send(self, mesg, 0)
  end

  def readpartial(maxlen, str = +'', buffer_pos = 0, raise_on_eof)
    result = Polyphony.backend_recv(self, str, maxlen, buffer_pos)
    raise EOFError if !result && raise_on_eof
    result
  end

  def read_nonblock(len, str = nil, exception: true)
    @io.read_nonblock(len, str, exception: exception)
  end

  def write_nonblock(buf, exception: true)
    @io.write_nonblock(buf, exception: exception)
  end
end