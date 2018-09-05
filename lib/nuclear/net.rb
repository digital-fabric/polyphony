# frozen_string_literal: true
export :Server, :Socket

require 'socket'

Reactor = import('./reactor')
Concurrency = import('./concurrency')
IO = import('./io')

class Server
  def initialize(opts = {})
    @opts = opts
    @callbacks = {}
  end

  def listen(opts)
    @server = TCPServer.new(opts[:host] || '127.0.0.1', opts[:port])
    Reactor.watch(@server, :r) { accept_from_socket }
  end

  def listening?
    @server
  end

  def close
    Reactor.unwatch(@server)
    @server.close
    @server = nil
  end

  def accept_from_socket
    socket = @server.accept
    if socket
      @callbacks[:connection]&.(Socket.new(socket))
    end
  rescue => e
    puts "error in accept_from_socket"
    p e
    puts e.backtrace.join("\n")
  end

  def on(event, &block)
    @callbacks[event] = block
  end

  def connection(&block)
    Concurrency.promise(then: block, catch: block) do |p|
      @callbacks[:connection] = p.to_proc
    end
  end

  def each_connection(&block)
    Concurrency.promise(recurring: true) do |p|
      @callbacks[:connection] = p.to_proc
    end.each(&block)
  end
end

class Socket < IO
  def initialize(socket, opts = {})
    super(socket, opts)
  end

  def connect(hostname, port, opts = {})
    Concurrency::Promise.new do |p|
      socket = ::Socket.new(::Socket::AF_INET, ::Socket::SOCK_STREAM)
      if opts[:timeout]
        p.timeout(opts[:timeout]) { connect_timeout(socket) }
      end
      connect_async(socket, hostname, port, opts, p)
    end
  end

  def connected?
    @open
  end

  def setsockopt(*args)
    @socket.setsockopt(*args)
  end

  def connect_async(socket, hostname, port, opts, promise)
    result = socket.connect_nonblock ::Socket.sockaddr_in(port, hostname), exception: false
    puts "connect_nonblock result: #{result.inspect}"
    case result
    when :wait_writable
      connect_async_in_progress(socket, hostname, port, opts, promise)
    when 0
      connect_success(socket, promise)
    else
      raise RuntimeError, "Invalid result from connect_nonblock: #{result.inspect}"
    end
  rescue => e
    promise.error(e)
  end

  def connect_async_in_progress(socket, hostname, port, opts, promise)
    Reactor.watch(socket, :rw) do |monitor|
      if monitor.writable? && !@socket
        connect_async(socket, hostname, port, opts, promise)
      end
      if monitor.readable?
        read_from_socket
      end
    end
  end

  def connect_success(socket, promise)
    @socket = socket
    @connected = true
    promise.resolve(socket)
  end

  def connect_timeout(socket)
    Reactor.unwatch(socket)
  end
end