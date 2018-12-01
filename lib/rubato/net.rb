# frozen_string_literal: true

export  :tcp_connect,
        :tcp_listen,
        :getaddrinfo

require 'socket'
require 'openssl'

class ::Socket
  def accept
    loop do
      result, client_addr = accept_nonblock(::IO::NO_EXCEPTION)
      case result
      when Socket         then return result
      when :wait_readable then read_watcher.await
      else
        raise "failed to accept (#{result.inspect})"
      end
    end
  ensure
    @read_watcher&.stop
  end

  def connect(remotesockaddr)
    loop do
      result = connect_nonblock(remotesockaddr, ::IO::NO_EXCEPTION)
      case result
      when 0              then return
      when :wait_writable then write_watcher.await
      else                raise IOError
      end
    end
  ensure
    @write_watcher&.stop
  end

  def recvfrom(maxlen, flags = 0)
    @read_buffer ||= +''
    loop do
      result = recvfrom_nonblock(maxlen, flags, @read_buffer, ::IO::NO_EXCEPTION)
      case result
      when nil            then raise IOError
      when :wait_readable then read_watcher.await
      else                return result
      end
    end
  ensure
    @read_watcher&.stop
  end

  class << self
    alias_method :orig_getaddrinfo, :getaddrinfo
    def getaddrinfo(*args)
      Rubato::ThreadPool.process { orig_getaddrinfo(*args) }
    end
  end
end

def tcp_connect(host, port, opts = {})
  ::Socket.new(:INET, :STREAM).tap { |s|
    addr = ::Socket.sockaddr_in(port, host)
    s.connect(addr)
  }
end

def tcp_listen(host = nil, port = nil, opts = {})
  host ||= '0.0.0.0'
  raise "Port number not specified" unless port
  ::Socket.new(:INET, :STREAM).tap { |s|
    addr = ::Socket.sockaddr_in(port, host)
    s.bind(addr)
    s.listen(0)
  }
end

class ::TCPServer
  def accept
    loop do
      result, client_addr = accept_nonblock(::IO::NO_EXCEPTION)
      case result
      when TCPSocket         then return result
      when :wait_readable then read_watcher.await
      else
        raise "failed to accept (#{result.inspect})"
      end
    end
  ensure
    @read_watcher&.stop
  end
end