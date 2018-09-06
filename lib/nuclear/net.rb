# frozen_string_literal: true

export :Server, :Socket

require 'socket'
require 'openssl'

Core  = import('./core')
IO    = import('./io')

# Implements a TCP server
class Server
  # Initializes server
  def initialize(opts = {})
    @opts = opts
    @callbacks = {}
  end

  # Listens on host and port given in opts
  # @param opts [Hash] options
  # @return [void]
  def listen(opts)
    @secure_context = opts[:secure_context]
    @server = opts[:socket] || create_server_socket(opts)
    Core::Reactor.watch(@server, :r) { accept_from_socket }
  end

  def create_server_socket(opts)
    socket = TCPServer.new(opts[:host] || '127.0.0.1', opts[:port])
    if @secure_context
      socket = OpenSSL::SSL::SSLServer.new(socket, @secure_context)
      socket.start_immediately = false
    end
    socket
  end

  # Returns true if server is listening
  # @return [Boolean]
  def listening?
    @server
  end

  # Closes the server socket
  # @return [void]
  def close
    Core::Reactor.unwatch(@server)
    @server.close
    @server = nil
  end

  # Accepts an incoming connection, triggers the :connection callback
  # @return [void]
  def accept_from_socket
    socket = @server.accept
    setup_connection(socket) if socket
  rescue StandardError => e
    puts "error in accept_from_socket: #{e.inspect}"
    puts e.backtrace.join("\n")
  end

  def setup_connection(socket)
    opts = { connected: true, secure_context: @secure_context }
    if @secure_context
      connection = SecureSocket.new(socket, opts)
      connection.on(:handshake, &@callbacks[:connection])
    else
      connection = Socket.new(socket, opts)
      @callbacks[:connection]&.(connection)
    end
    # klass = @secure_context ? SecureSocket : Socket
    # klass.new(socket, connected: true, secure_context: @secure_context)
    
  end

  # Registers a callback for given event
  # @param event [Symbol] event kind
  # @return [void]
  def on(event, &block)
    @callbacks[event] = block
  end

  # Returns a promise fulfilled upon the first incoming connection
  # @return [Promise]
  def connection(&block)
    Core::Async.promise(then: block, catch: block) do |p|
      @callbacks[:connection] = p.to_proc
    end
  end

  # Creates a generator promise, iterating asynchronously over incoming
  # connections
  # @return [void]
  def each_connection(&block)
    Core::Async.promise(recurring: true) do |p|
      @callbacks[:connection] = p.to_proc
    end.each(&block)
  end
end

# Client connection functionality
module ClientConnection
  # Connects to the given host & port, returning a promise fulfilled once
  # connected. Options can include:
  #   :timeout => connection timeout in seconds
  # @param host [String] host domain name or IP address
  # @param port [Integer] port number
  # @param opts [Hash] options
  # @return [Promise] connection promise
  def connect(host, port, opts = {})
    Core::Async.promise do |p|
      socket = ::Socket.new(::Socket::AF_INET, ::Socket::SOCK_STREAM)
      p.timeout(opts[:timeout]) { connect_timeout(socket) } if opts[:timeout]
      connect_async(socket, host, port, p)
    end
  end

  # Connects asynchronously to a TCP Server
  # @param socket [TCPSocket] socket to use for connection
  # @param host [String] host domain name or ip address
  # @param port [Integer] server port number
  # @param promise [Promise] connection promise
  # @return [void]
  def connect_async(socket, host, port, promise)
    addr = ::Socket.sockaddr_in(port, host)
    result = socket.connect_nonblock addr, exception: false
    handle_connect_result(result, socket, host, port, promise)
  rescue StandardError => e
    promise.error(e)
  end

  # Handles result of asynchronous connection
  # @param result [Integer, Symbol, nil] result of call to IO#connect_nonblock
  # @param socket [TCPSocket] socket to use for connection
  # @param host [String] host domain name or ip address
  # @param port [Integer] server port number
  # @param promise [Promise] connection promise
  # @return [void]
  def handle_connect_result(result, socket, host, port, promise)
    case result
    when :wait_writable
      connect_async_pending(socket, host, port, promise)
    when 0
      @connection_pending = false
      connect_success(socket, promise)
    else
      handle_invalid_connect_result(result, socket)
    end
  end

  # Handles result of asynchronous connection
  # @param result [Integer, Symbol, nil] result of call to IO#connect_nonblock
  # @param socket [TCPSocket] socket to use for connection
  def handle_invalid_connect_result(result, socket)
    invalid_connect_result(result, socket)
    @connection_pending = false
    Core::Reactor.unwatch(socket)
    @monitor = nil
    raise "Invalid result from connect_nonblock: #{result.inspect}"
  end

  # Sets connection pending state
  # @param socket [TCPSocket] socket to use for connection
  # @param host [String] host domain name or ip address
  # @param port [Integer] server port number
  # @param promise [Promise] connection promise
  # @return [void]
  def connect_async_pending(socket, host, port, promise)
    @monitor = create_monitor(socket, :rw)
    @connection_pending = [socket, host, port, promise]
  end

  # Overrides IO#write_to_io to support async connection
  # @return [void]
  def write_to_io
    @connection_pending ? connect_async(*@connection_pending) : super
  end

  # Sets socket and connected status on successful connection
  # @param socket [TCPSocket] TCP socket
  # @param promise [Promise] connection promise
  # @return [void]
  def connect_success(socket, promise)
    @io = socket
    @connected = true
    update_monitor_interests(:r)
    promise.resolve(socket)
  end

  # Called upon connection timeout, cleans up
  # @param socket [TCPSocket] TCP socket
  # @return [void]
  def connect_timeout(socket)
    @connection_pending = false
    Core::Reactor.unwatch(socket)
    @monitor = nil
    socket.close
  end
end

# Encapsulates a TCP socket
class Socket < IO
  include ClientConnection

  # Initializes socket
  def initialize(socket = nil, opts = {})
    super(socket, opts)
    @connected = opts[:connected]
  end

  # Returns true if socket is connected
  # @return [Boolean]
  def connected?
    @connected
  end

  def secure?
    false
  end

  # Sets socket option
  # @return [void]
  def setsockopt(*args)
    @io.setsockopt(*args)
  end
end

# Socket with TLS handshake functionality
class SecureSocket < Socket
  # Initializes secure socket
  def initialize(socket = nil, opts = {})
    super(socket, opts.merge(watch: false))
    accept_secure_handshake
  end

  def secure?
    true
  end

  # accepts secure handshake asynchronously
  # @return [void]
  def accept_secure_handshake
    @pending_secure_handshake = true
    result = @io.accept_nonblock(exception: false)
    handle_accept_secure_handshake_result(result)
  rescue StandardError => e
    close_on_error(e)
  end

  # Handles result of secure handshake
  # @param result [Integer, any] result of call to accept_nonblock
  # @return [void]
  def handle_accept_secure_handshake_result(result)
    case result
    when :wait_readable
      update_monitor_interests(:r)
    when :wait_writable
      update_monitor_interests(:w)
    else
      @pending_secure_handshake = false
      update_monitor_interests(:r)
      @callbacks[:handshake]&.(self)
    end
  end

  # Overrides handle_selected to accept secure handshake
  # @param monitor [NIO::Monitor] associated monitor
  # @return [void]
  def handle_selected(monitor)
    @pending_secure_handshake ? accept_secure_handshake : super(monitor)
  end
end
