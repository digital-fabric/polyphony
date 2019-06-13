# frozen_string_literal: true

require 'socket'

import('./io')

class ::Socket
  NO_EXCEPTION = { exception: false }.freeze

  def connect(remotesockaddr)
    loop do
      result = connect_nonblock(remotesockaddr, NO_EXCEPTION)
      case result
      when 0              then return
      when :wait_writable then write_watcher.await
      else                raise IOError
      end
    end
  ensure
    @write_watcher&.stop
  end

  def recv(maxlen, flags = 0, outbuf = nil)
    outbuf ||= +''
    loop do
      result = recv_nonblock(maxlen, flags, outbuf, NO_EXCEPTION)
      case result
      when :wait_readable
        read_watcher.await
      else
        return result
      end
    end
  end

  def recvfrom(maxlen, flags = 0)
    @read_buffer ||= +''
    loop do
      result = recvfrom_nonblock(maxlen, flags, @read_buffer, NO_EXCEPTION)
      case result
      when nil            then raise IOError
      when :wait_readable then read_watcher.await
      else                return result
      end
    end
  ensure
    @read_watcher&.stop
  end

  ZERO_LINGER = [0, 0].pack("ii")

  def dont_linger
    setsockopt(Socket::SOL_SOCKET, Socket::SO_LINGER, ZERO_LINGER)
  end

  def no_delay
    setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
  end

  def reuse_addr
    setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, 1)
  end

  class << self
    alias_method :orig_getaddrinfo, :getaddrinfo
    def getaddrinfo(*args)
      Polyphony::ThreadPool.process { orig_getaddrinfo(*args) }
    end
  end
end

class ::TCPSocket
  NO_EXCEPTION = { exception: false }.freeze

  def foo; :bar; end

  def initialize(remote_host, remote_port, local_host=nil, local_port=nil)
    @io = Socket.new Socket::AF_INET, Socket::SOCK_STREAM
    if local_host && local_port
      @io.bind(Addrinfo.tcp(local_host, local_port))
    end
    @io.connect(Addrinfo.tcp(remote_host, remote_port)) if remote_host
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
end

class ::TCPServer
  def initialize(hostname = nil, port)
    @io = Socket.new Socket::AF_INET, Socket::SOCK_STREAM
    @io.bind(Addrinfo.tcp(hostname, port))
    @io.listen(0)
  end

  alias_method :orig_accept, :accept
  def accept
    @io ? @io.accept : orig_accept
  end
end