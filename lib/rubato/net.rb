# frozen_string_literal: true

export  :SocketWrapper,
        :tcp_connect,
        :tcp_listen,
        :getaddrinfo

require 'socket'
require 'openssl'

RubatoIO = import('./io')

def tcp_connect(host, port, opts = {})
  socket = ::Socket.new(:INET, :STREAM)
  SocketWrapper.new(socket, opts).tap do |o|
    o.connect(host, port)
  end
end

def tcp_listen(host = '0.0.0.0', port = nil, opts = {})
  host ||= '0.0.0.0'
  raise "Port number not specified" unless port
  socket = ::Socket.new(:INET, :STREAM)
  SocketWrapper.new(socket, opts).tap do |server|
    server.bind(host, port)
    server.listen
  end
end

def getaddrinfo(host, port)
  Rubato::ThreadPool.process { Socket.getaddrinfo(host, port, :INET, :STREAM) }
end

class SocketWrapper < RubatoIO::IOWrapper
  def initialize(io, opts = {})
    super

    reuse_addr   if opts[:reuse_addr]
    dont_linger  if opts[:dont_linger]

    setup_secure_context if @opts[:secure] || @opts[:secure_context]
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

  def setup_secure_context
    if @opts[:secure_context] && !@opts[:secure]
      @opts[:secure] = true
    elsif @opts[:secure] && !@opts[:secure_context]
      @opts[:secure_context] = OpenSSL::SSL::SSLContext.new
      @opts[:secure_context].set_params(verify_mode: OpenSSL::SSL::VERIFY_PEER)
    end
    setup_alpn(opts[:alpn_protocols]) if opts[:alpn_protocols]
  end

  def setup_alpn(protocols)
    @opts[:secure_context].alpn_protocols = protocols
    @opts[:secure_context].alpn_select_cb = proc do |peer_protocols|
      # select first common protocol
      (protocols & peer_protocols).first
    end
  end

  def connect(host, port)
    addr = ::Socket.sockaddr_in(port, host)
    puts "*" * 40
    p addr
    loop do
      result = @io.connect_nonblock(addr, exception: false)
      case result
      when 0              then break
      when :wait_writable then write_watcher.await
      else                raise IOError
      end
    end
    connect_ssl_handshake if @opts[:secure]
  ensure
    @write_watcher&.stop
  end

  def connect_ssl_handshake
    puts "connect_ssl_handshake"
    @io_raw = @io
    @io = OpenSSL::SSL::SSLSocket.new(@io_raw, @opts[:secure_context])
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
    socket = accept_socket
    SocketWrapper.new(socket, accept_opts).tap do |wrapper|
      wrapper.accept_ssl_handshake if @opts[:secure]
    end
  end

  def accept_socket
    loop do
      result, client_addr = @io.accept_nonblock(exception: false)
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

  def accept_ssl_handshake
    @io_raw = @io
    @io = OpenSSL::SSL::SSLSocket.new(@io_raw, @opts[:secure_context])

    loop do
      result = @io.accept_nonblock(exception: false)
      case result
      when :wait_readable
        read_watcher.await
      when :wait_writable
        write_watcher.await
      else
        break true
      end
    end
  ensure
    @read_watcher&.stop
    @write_watcher&.stop
  end

  def alpn_protocol
    @opts[:secure] && @io.alpn_protocol
  end

  def accept_opts
    @accept_opts ||= @opts.merge(reuse_addr: nil, dont_linger: nil)
  end

  def bind(host, port)
    addr = ::Socket.sockaddr_in(port, host)
    @io.bind(addr)
  end

  def listen(backlog = 0)
    @io.listen(backlog)
  end
end
