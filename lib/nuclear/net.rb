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
    @watcher = EV::IO.new(@server, :r, true) { accept_from_socket }
  end

  # Creates a server socket for listening to incoming connections
  # @param opts [Hash] listening options
  # @return [Net::Socket]
  def create_server_socket(opts)
    socket = TCPServer.new(opts[:host] || '127.0.0.1', opts[:port])
    if @secure_context
      socket = OpenSSL::SSL::SSLServer.new(socket, @secure_context)
      socket.start_immediately = false
      setup_alpn(opts[:alpn_protocols]) if opts[:alpn_protocols]
    end
    socket
  end

  # Sets up ALPN protocols negotiated during handshake
  # @param server_protocols [Array<String>] protocols supported by server
  # @return [void]
  def setup_alpn(server_protocols)
    @secure_context.alpn_protocols = server_protocols
    @secure_context.alpn_select_cb = proc do |client_protocols|
      # select first common protocol
      (server_protocols & client_protocols).first
    end
  end

  # Returns true if server is listening
  # @return [Boolean]
  def listening?
    @server
  end

  # Closes the server socket
  # @return [void]
  def close
    Core.unwatch(@server)
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

  # Sets up an accepted connection
  # @param socket [TCPSocket] accepted socket
  # @return [Net::Socket]
  def setup_connection(socket)
    opts = { connected: true, secure_context: @secure_context }
    if @secure_context
      connection = SecureSocket.new(socket, opts)
      connection.on(:handshake, &@callbacks[:connection])
    else
      connection = Socket.new(socket, opts)
      @callbacks[:connection]&.(connection)
    end
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
    Core.promise(then: block, catch: block) do |p|
      @callbacks[:connection] = p.to_proc
    end
  end

  # Creates a generator promise, iterating asynchronously over incoming
  # connections
  # @return [void]
  def each_connection(&block)
    Core.promise(recurring: true) do |p|
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
    Core.promise do |p|
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
    promise.reject(e)
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
    Core.unwatch(socket)
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
    create_watcher(socket, :rw)
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
    update_event_mask(:r)
    promise.resolve(socket)
  end

  # Called upon connection timeout, cleans up
  # @param socket [TCPSocket] TCP socket
  # @return [void]
  def connect_timeout(socket)
    @connection_pending = false
    Core.unwatch(socket)
    @monitor = nil
    socket.close
  end
end

# ALPN protocol
module ALPN
  # returns the ALPN protocol used for the given socket
  # @return [String, nil]
  def alpn_protocol
    secure? && raw_io.alpn_protocol
  end
end

# Encapsulates a TCP socket
class Socket < IO
  include ClientConnection
  include ALPN

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

  # Returns false
  # @return [false]
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
    super
    accept_secure_handshake
  end

  # Returns true
  # @return [true]
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
      @watcher_r.start
    when :wait_writable
      @watcher_w.start
    else
      @pending_secure_handshake = false
      @watcher_r.start
      @watcher_w.stop
      @callbacks[:handshake]&.(self)
    end
  end

  # Overrides read_from_io to accept secure handshake
  # @return [void]
  def read_from_io
    @pending_secure_handshake ? accept_secure_handshake : super
  end
end
