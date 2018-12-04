# frozen_string_literal: true

export  :tcp_connect,
        :tcp_listen,
        :getaddrinfo

require 'socket'
require 'openssl'

def tcp_connect(host, port, opts = {})
  socket = ::Socket.new(:INET, :STREAM).tap { |s|
    addr = ::Socket.sockaddr_in(port, host)
    s.connect(addr)
  }
  if opts[:secure_context] || opts[:secure]
    secure_socket(socket, opts[:secure_context], opts)
  else
    socket
  end
end

def tcp_listen(host = nil, port = nil, opts = {})
  host ||= '0.0.0.0'
  raise "Port number not specified" unless port
  socket = ::Socket.new(:INET, :STREAM).tap { |s|
    addr = ::Socket.sockaddr_in(port, host)
    s.bind(addr)
    s.listen(0)
  }
  if opts[:secure_context] || opts[:secure]
    secure_server(socket, opts[:secure_context], opts)
  else
    socket
  end
end

DEFAULT_SSL_CONTEXT = OpenSSL::SSL::SSLContext.new
# DEFAULT_SSL_CONTEXT.set_params(verify_mode: OpenSSL::SSL::VERIFY_PEER)

def secure_socket(socket, context, opts)
  context ||= DEFAULT_SSL_CONTEXT
  setup_alpn(context, opts[:alpn_protocols]) if opts[:alpn_protocols]
  OpenSSL::SSL::SSLSocket.new(socket, context).tap { |s| s.connect }
end

def secure_server(socket, context, opts)
  context ||= DEFAULT_SSL_CONTEXT
  setup_alpn(context, opts[:alpn_protocols]) if opts[:alpn_protocols]
  OpenSSL::SSL::SSLServer.new(socket, context)
end

def setup_alpn(context, protocols)
  context.alpn_protocols = protocols
  context.alpn_select_cb = ->(peer_protocols) {
    (protocols & peer_protocols).first
  }
end

################################################################################

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

class ::OpenSSL::SSL::SSLSocket
  def accept
    loop do
      result = accept_nonblock(::IO::NO_EXCEPTION)
      case result
      when :wait_readable then io.read_watcher.await
      when :wait_writable then io.write_watcher.await
      else                     return true
      end
    end
  ensure
    io.stop_watchers
  end

  def connect
    loop do
      result = connect_nonblock(::IO::NO_EXCEPTION)
      case result
      when :wait_readable then io.read_watcher.await
      when :wait_writable then io.write_watcher.await
      else                     return true
      end
    end
  ensure
    io.stop_watchers
  end

  def read(max = 8192)
    @read_buffer ||= +''
    loop do
      result = read_nonblock(max, @read_buffer, ::IO::NO_EXCEPTION)
      case result
      when nil            then raise ::IOError
      when :wait_readable then io.read_watcher.await
      else                return result
      end
    end
  ensure
    io.stop_watchers
  end

  def write(data)
    loop do
      result = write_nonblock(data, ::IO::NO_EXCEPTION)
      case result
      when nil            then raise ::IOError
      when :wait_writable then io.write_watcher.await
      else
        (result == data.bytesize) ? (return result) : (data = data[result..-1])
      end
    end
  ensure
    io.stop_watchers
  end
end