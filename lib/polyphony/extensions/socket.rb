# frozen_string_literal: true

require 'socket'

require_relative './io'
require_relative '../core/thread_pool'

# BasicSocket extensions
class BasicSocket
  # Returns `:backend_recv`. This method is used to tell parsers which read
  # method to use for this object.
  #
  # @return [:backend_recv] use Polyphony.backend_recv to parse from socket
  def __read_method__
    :backend_recv
  end

  def __write_method__
    :backend_send
  end
end

# Socket extensions # TODO: rewrite in C
class ::Socket

  # Accepts an incoming connection.
  
  # @return [TCPSocket] new connection
  def accept
    Polyphony.backend_accept(self, TCPSocket)
  end

  # call-seq:
  #   socket.accept_loop { |conn| ... }
  #
  # Accepts incoming connections in an infinite loop.
  #
  # @param &block [Proc] handler block
  # @return [void]
  def accept_loop(&block)
    Polyphony.backend_accept_loop(self, TCPSocket, &block)
  end

  NO_EXCEPTION = { exception: false }.freeze

  # Connects to the given address
  #
  # @param addr [AddrInfo, String] address to connect to
  # @return [::Socket] self
  def connect(addr)
    addr = Addrinfo.new(addr) if addr.is_a?(String)
    Polyphony.backend_connect(self, addr.ip_address, addr.ip_port)
    self
  end

  alias_method :orig_read, :read

  # call-seq:
  #   socket.read -> string
  #   socket.read(maxlen) -> string
  #   socket.read(maxlen, buf) -> buf
  #   socket.read(maxlen, buf, buf_pos) -> buf
  #
  # Reads from the socket. If `maxlen` is given, reads up to `maxlen` bytes from
  # the socket, otherwise reads to `EOF`. If `buf` is given, it is used as the
  # buffer to read into, otherwise a new string is allocated. If `buf_pos` is
  # given, reads into the given offset (in bytes) in the given buffer. If the
  # given buffer offset is negative, it is calculated from the current end of
  # the buffer (`-1` means the read data will be appended to the end of the
  # buffer).
  #
  # If no bytes are available and `EOF` is not hit, this method will block until
  # the socket is ready to read from.
  #
  # @param maxlen [Integer, nil] maximum bytes to read from socket
  # @param buf [String, nil] buffer to read into
  # @param buf_pos [Number] buffer position to read into
  # @return [String] buffer used for reading
  def read(maxlen = nil, buf = nil, buf_pos = 0)
    return Polyphony.backend_recv(self, buf, maxlen, buf_pos) if buf
    return Polyphony.backend_recv(self, +'', maxlen, 0) if maxlen

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

  # call-seq:
  #   socket.recv(maxlen) -> string
  #   socket.recv(maxlen, flags) -> string
  #   socket.recv(maxlen, flags, buf) -> buf
  #
  # Receives up to `maxlen` bytes from the socket. If `outbuf` is given, it is
  # used as the buffer to receive into, otherwise a new string is allocated and
  # used as buffer.
  #
  # If no bytes are available, this method will block until the socket is ready
  # to receive from.
  #
  # @param maxlen [Integer] maximum bytes to receive
  # @param flags [Integer] receive flags
  # @param outbuf [String, nil] buffer for reading or nil to allocate new string
  # @return [String] receive buffer
  def recv(maxlen, flags = 0, outbuf = nil)
    Polyphony.backend_recv(self, outbuf || +'', maxlen, 0)
  end

  # call-seq:
  #   socket.recv_loop { |data| ... }
  #   socket.recv_loop(maxlen) { |data| ... }
  #   socket.read_loop { |data| ... }
  #   socket.read_loop(maxlen) { |data| ... }
  #
  # Receives up to `maxlen` bytes at a time in an infinite loop. Read buffers
  # will be passed to the given block.
  #
  # @param maxlen [Integer] maximum bytes to receive
  # @param &block [Proc] handler block
  # @return [void]
  def recv_loop(maxlen = 8192, &block)
    Polyphony.backend_recv_loop(self, maxlen, &block)
  end
  alias_method :read_loop, :recv_loop

  # call-seq:
  #   socket.feed_loop(receiver, method)
  #   socket.feed_loop(receiver, method) { |result| ... }
  #
  # Receives data from the socket in an infinite loop, passing the data to the
  # given receiver using the given method. If a block is given, the result of
  # the method call to the receiver is passed to the block.
  #
  # This method can be used to feed data into parser objects. The following
  # example shows how to feed data from a socket directly into a MessagePack
  # unpacker:
  #
  #   unpacker = MessagePack::Unpacker.new
  #   buffer = []
  #   reader = spin do
  #     i.feed_loop(unpacker, :feed_each) { |msg| handle_msg(msg) }
  #   end
  #
  # @param receiver [any] receiver object
  # @param method [Symbol] method to call
  # @param &block [Proc] block to handle result of method call to receiver
  # @return [void]
  def feed_loop(receiver, method = :call, &block)
    Polyphony.backend_recv_feed_loop(self, receiver, method, &block)
  end

  # :no-doc:
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

  # call-seq:
  #   socket.readpartial(maxlen) -> string
  #   socket.readpartial(maxlen, buf) -> buf
  #   socket.readpartial(maxlen, buf, buf_pos) -> buf
  #   socket.readpartial(maxlen, buf, buf_pos, raise_on_eof) -> buf
  #
  # Reads up to `maxlen` from the socket. If `buf` is given, it is used as the
  # buffer to read into, otherwise a new string is allocated. If `buf_pos` is
  # given, reads into the given offset (in bytes) in the given buffer. If the
  # given buffer offset is negative, it is calculated from the current end of
  # the buffer (`-1` means the read data will be appended to the end of the
  # buffer). If `raise_on_eof` is `true` (the default,) an `EOFError` will be
  # raised on `EOF`, otherwise `nil` will be returned.
  #
  # If no bytes are available and `EOF` is not hit, this method will block until
  # the socket is ready to read from.
  #
  # @param maxlen [Integer, nil] maximum bytes to read from socket
  # @param buf [String, nil] buffer to read into
  # @param buf_pos [Number] buffer position to read into
  # @param raise_on_eof [bool] whether to raise an exception on `EOF`
  # @return [String, nil] buffer used for reading or nil on `EOF`
  def readpartial(maxlen, buf = +'', buf_pos = 0, raise_on_eof = true)
    result = Polyphony.backend_recv(self, buf, maxlen, buf_pos)
    raise EOFError if !result && raise_on_eof
  end

  ZERO_LINGER = [0, 0].pack('ii').freeze

  # Sets the linger option to 0.
  #
  # @return [::Socket] self
  def dont_linger
    setsockopt(Socket::SOL_SOCKET, Socket::SO_LINGER, ZERO_LINGER)
    self
  end

  # Sets the `NODELAY` option.
  #
  # @return [::Socket] self
  def no_delay
    setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
    self
  end

  # Sets the `REUSEADDR` option.
  #
  # @return [::Socket] self
  def reuse_addr
    setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, 1)
    self
  end

  # Sets the `REUSEPORT` option.
  #
  # @return [::Socket] self
  def reuse_port
    setsockopt(::Socket::SOL_SOCKET, ::Socket::SO_REUSEPORT, 1)
    self
  end

  class << self
    alias_method :orig_getaddrinfo, :getaddrinfo
    
    # Resolves the given addr using a worker thread from the default thread
    # pool.
    #
    # @return [AddrInfo]
    def getaddrinfo(*args)
      Polyphony::ThreadPool.process { orig_getaddrinfo(*args) }
    end
  end
end

# Overide stock TCPSocket code by encapsulating a Socket instance
class ::TCPSocket
  NO_EXCEPTION = { exception: false }.freeze

  attr_reader :io

  class << self
    alias_method :open, :new
  end

  # Initializes the socket.
  #
  # @param remote_host [String] remote host
  # @param remote_port [Integer] remote port
  # @param local_host [String] local host
  # @param local_port [Integer] local port
  def initialize(remote_host, remote_port, local_host = nil, local_port = nil)
    remote_addr = Addrinfo.tcp(remote_host, remote_port)
    @io = Socket.new remote_addr.afamily, Socket::SOCK_STREAM
    if local_host && local_port
      addr = Addrinfo.tcp(local_host, local_port)
      @io.bind(addr)
    end

    return unless remote_host && remote_port

    addr = Addrinfo.tcp(remote_host, remote_port)
    @io.connect(addr)
  end

  alias_method :orig_close, :close
  
  # Closes the socket.
  #
  # @return [TCPSocket] self
  def close
    @io ? @io.close : orig_close
    self
  end

  alias_method :orig_setsockopt, :setsockopt
  
  # Calls `setsockopt` with the given arguments.
  #
  # @return [TCPSocket] self
  def setsockopt(*args)
    @io ? @io.setsockopt(*args) : orig_setsockopt(*args)
    self
  end

  alias_method :orig_closed?, :closed?
  
  # Returns true if the socket is closed.
  #
  # @return [bool] is socket closed
  def closed?
    @io ? @io.closed? : orig_closed?
  end

  # Sets the linger option to 0.
  #
  # @return [::Socket] self
  def dont_linger
    setsockopt(Socket::SOL_SOCKET, Socket::SO_LINGER, ZERO_LINGER)
    self
  end

  # Sets the `NODELAY` option.
  #
  # @return [::Socket] self
  def no_delay
    setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
    self
  end

  # Sets the `REUSEADDR` option.
  #
  # @return [::Socket] self
  def reuse_addr
    setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, 1)
    self
  end

  # Sets the `REUSEPORT` option.
  #
  # @return [::Socket] self
  def reuse_port
    setsockopt(::Socket::SOL_SOCKET, ::Socket::SO_REUSEPORT, 1)
    self
  end

  alias_method :orig_read, :read

  # call-seq:
  #   socket.read -> string
  #   socket.read(maxlen) -> string
  #   socket.read(maxlen, buf) -> buf
  #   socket.read(maxlen, buf, buf_pos) -> buf
  #
  # Reads from the socket. If `maxlen` is given, reads up to `maxlen` bytes from
  # the socket, otherwise reads to `EOF`. If `buf` is given, it is used as the
  # buffer to read into, otherwise a new string is allocated. If `buf_pos` is
  # given, reads into the given offset (in bytes) in the given buffer. If the
  # given buffer offset is negative, it is calculated from the current end of
  # the buffer (`-1` means the read data will be appended to the end of the
  # buffer).
  #
  # If no bytes are available and `EOF` is not hit, this method will block until
  # the socket is ready to read from.
  #
  # @param maxlen [Integer, nil] maximum bytes to read from socket
  # @param buf [String, nil] buffer to read into
  # @param buf_pos [Number] buffer position to read into
  # @return [String] buffer used for reading
  def read(maxlen = nil, buf = nil, buf_pos = 0)
    return Polyphony.backend_recv(self, buf, maxlen, buf_pos) if buf
    return Polyphony.backend_recv(self, +'', maxlen, 0) if maxlen

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

  # call-seq:
  #   socket.recv(maxlen) -> string
  #   socket.recv(maxlen, flags) -> string
  #   socket.recv(maxlen, flags, buf) -> buf
  #
  # Receives up to `maxlen` bytes from the socket. If `outbuf` is given, it is
  # used as the buffer to receive into, otherwise a new string is allocated and
  # used as buffer.
  #
  # If no bytes are available, this method will block until the socket is ready
  # to receive from.
  #
  # @param maxlen [Integer] maximum bytes to receive
  # @param flags [Integer] receive flags
  # @param outbuf [String, nil] buffer for reading or nil to allocate new string
  # @return [String] receive buffer
  def recv(maxlen, flags = 0, outbuf = nil)
    Polyphony.backend_recv(self, outbuf || +'', maxlen, 0)
  end

  # call-seq:
  #   socket.recv_loop { |data| ... }
  #   socket.recv_loop(maxlen) { |data| ... }
  #   socket.read_loop { |data| ... }
  #   socket.read_loop(maxlen) { |data| ... }
  #
  # Receives up to `maxlen` bytes at a time in an infinite loop. Read buffers
  # will be passed to the given block.
  #
  # @param maxlen [Integer] maximum bytes to receive
  # @param &block [Proc] handler block
  # @return [void]
  def recv_loop(maxlen = 8192, &block)
    Polyphony.backend_recv_loop(self, maxlen, &block)
  end
  alias_method :read_loop, :recv_loop

  # call-seq:
  #   socket.feed_loop(receiver, method)
  #   socket.feed_loop(receiver, method) { |result| ... }
  #
  # Receives data from the socket in an infinite loop, passing the data to the
  # given receiver using the given method. If a block is given, the result of
  # the method call to the receiver is passed to the block.
  #
  # This method can be used to feed data into parser objects. The following
  # example shows how to feed data from a socket directly into a MessagePack
  # unpacker:
  #
  #   unpacker = MessagePack::Unpacker.new
  #   buffer = []
  #   reader = spin do
  #     i.feed_loop(unpacker, :feed_each) { |msg| handle_msg(msg) }
  #   end
  #
  # @param receiver [any] receiver object
  # @param method [Symbol] method to call
  # @param &block [Proc] block to handle result of method call to receiver
  # @return [void]
  def feed_loop(receiver, method = :call, &block)
    Polyphony.backend_recv_feed_loop(self, receiver, method, &block)
  end

  # call-seq:
  #   socket.readpartial(maxlen) -> string
  #   socket.readpartial(maxlen, buf) -> buf
  #   socket.readpartial(maxlen, buf, buf_pos) -> buf
  #   socket.readpartial(maxlen, buf, buf_pos, raise_on_eof) -> buf
  #
  # Reads up to `maxlen` from the socket. If `buf` is given, it is used as the
  # buffer to read into, otherwise a new string is allocated. If `buf_pos` is
  # given, reads into the given offset (in bytes) in the given buffer. If the
  # given buffer offset is negative, it is calculated from the current end of
  # the buffer (`-1` means the read data will be appended to the end of the
  # buffer). If `raise_on_eof` is `true` (the default,) an `EOFError` will be
  # raised on `EOF`, otherwise `nil` will be returned.
  #
  # If no bytes are available and `EOF` is not hit, this method will block until
  # the socket is ready to read from.
  #
  # @param maxlen [Integer, nil] maximum bytes to read from socket
  # @param buf [String, nil] buffer to read into
  # @param buf_pos [Number] buffer position to read into
  # @param raise_on_eof [bool] whether to raise an exception on `EOF`
  # @return [String, nil] buffer used for reading or nil on `EOF`
  def readpartial(maxlen, str = +'', buffer_pos = 0, raise_on_eof = true)
    result = Polyphony.backend_recv(self, str, maxlen, buffer_pos)
    raise EOFError if !result && raise_on_eof
    result
  end

  # Performs a non-blocking read from the socket of up to `maxlen` bytes. If
  # `buf` is given, it is used as the read buffer, otherwise a new string will
  # be allocated. If the socket is not ready for reading and `exception` is
  # true, an `IO::WaitReadable` will be raised. If the socket is not ready for
  # reading and `exception` is false, `:wait_readable` is returned.
  #
  # @param maxlen [Integer] maximum bytes to read
  # @param buf [String, nil] read buffer
  # @param exception [bool] whether to raise an exception if not ready for reading
  # @return [String, :wait_readable] read buffer
  def read_nonblock(len, buf = nil, exception: true)
    @io.read_nonblock(len, buf, exception: exception)
  end

  # Performs a non-blocking to the socket. If the socket is not ready for
  # writing and `exception` is true, an `IO::WaitWritable` will be raised. If
  # the socket is not ready for writing and `exception` is false,
  # `:wait_writable` is returned.
  #
  # @param buf [String, nil] write buffer
  # @param exception [bool] whether to raise an exception if not ready for reading
  # @return [Integer, :wait_readable] number of bytes written
  def write_nonblock(buf, exception: true)
    @io.write_nonblock(buf, exception: exception)
  end
end

# TCPServer extensions
class ::TCPServer

  # Initializes the TCP server socket.
  #
  # @param hostname [String, nil] hostname to connect to
  # @param port [Integer] port to connect to
  def initialize(hostname = nil, port = 0)
    addr = Addrinfo.tcp(hostname, port)
    @io = Socket.new addr.afamily, Socket::SOCK_STREAM
    @io.bind(addr)
    @io.listen(0)
  end

  alias_method :orig_accept, :accept

  # Accepts an incoming connection.
  
  # @return [TCPSocket] new connection
  def accept
    Polyphony.backend_accept(@io, TCPSocket)
  end

  # call-seq:
  #   socket.accept_loop { |conn| ... }
  #
  # Accepts incoming connections in an infinite loop.
  #
  # @param &block [Proc] handler block
  # @return [void]
  def accept_loop(&block)
    Polyphony.backend_accept_loop(@io, TCPSocket, &block)
  end

  alias_method :orig_close, :close
  
  # Closes the server socket.
  #
  # @return [TCPServer] self
  def close
    @io.close
    self
  end
end

class ::UNIXServer
  alias_method :orig_accept, :accept

  # Accepts an incoming connection.
  
  # @return [UNIXSocket] new connection
  def accept
    Polyphony.backend_accept(self, UNIXSocket)
  end

  # call-seq:
  #   socket.accept_loop { |conn| ... }
  #
  # Accepts incoming connections in an infinite loop.
  #
  # @param &block [Proc] handler block
  # @return [void]
  def accept_loop(&block)
    Polyphony.backend_accept_loop(self, UNIXSocket, &block)
  end
end

class ::UNIXSocket
  alias_method :orig_read, :read
  
  # call-seq:
  #   socket.read -> string
  #   socket.read(maxlen) -> string
  #   socket.read(maxlen, buf) -> buf
  #   socket.read(maxlen, buf, buf_pos) -> buf
  #
  # Reads from the socket. If `maxlen` is given, reads up to `maxlen` bytes from
  # the socket, otherwise reads to `EOF`. If `buf` is given, it is used as the
  # buffer to read into, otherwise a new string is allocated. If `buf_pos` is
  # given, reads into the given offset (in bytes) in the given buffer. If the
  # given buffer offset is negative, it is calculated from the current end of
  # the buffer (`-1` means the read data will be appended to the end of the
  # buffer).
  #
  # If no bytes are available and `EOF` is not hit, this method will block until
  # the socket is ready to read from.
  #
  # @param maxlen [Integer, nil] maximum bytes to read from socket
  # @param buf [String, nil] buffer to read into
  # @param buf_pos [Number] buffer position to read into
  # @return [String] buffer used for reading
  def read(maxlen = nil, buf = nil, buf_pos = 0)
    return Polyphony.backend_recv(self, buf, maxlen, buf_pos) if buf
    return Polyphony.backend_recv(self, +'', maxlen, 0) if maxlen

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

  # call-seq:
  #   socket.recv(maxlen) -> string
  #   socket.recv(maxlen, flags) -> string
  #   socket.recv(maxlen, flags, buf) -> buf
  #
  # Receives up to `maxlen` bytes from the socket. If `outbuf` is given, it is
  # used as the buffer to receive into, otherwise a new string is allocated and
  # used as buffer.
  #
  # If no bytes are available, this method will block until the socket is ready
  # to receive from.
  #
  # @param maxlen [Integer] maximum bytes to receive
  # @param flags [Integer] receive flags
  # @param outbuf [String, nil] buffer for reading or nil to allocate new string
  # @return [String] receive buffer
  def recv(maxlen, flags = 0, outbuf = nil)
    Polyphony.backend_recv(self, outbuf || +'', maxlen, 0)
  end

  # call-seq:
  #   socket.recv_loop { |data| ... }
  #   socket.recv_loop(maxlen) { |data| ... }
  #   socket.read_loop { |data| ... }
  #   socket.read_loop(maxlen) { |data| ... }
  #
  # Receives up to `maxlen` bytes at a time in an infinite loop. Read buffers
  # will be passed to the given block.
  #
  # @param maxlen [Integer] maximum bytes to receive
  # @param &block [Proc] handler block
  # @return [void]
  def recv_loop(maxlen = 8192, &block)
    Polyphony.backend_recv_loop(self, maxlen, &block)
  end
  alias_method :read_loop, :recv_loop

  # call-seq:
  #   socket.feed_loop(receiver, method)
  #   socket.feed_loop(receiver, method) { |result| ... }
  #
  # Receives data from the socket in an infinite loop, passing the data to the
  # given receiver using the given method. If a block is given, the result of
  # the method call to the receiver is passed to the block.
  #
  # This method can be used to feed data into parser objects. The following
  # example shows how to feed data from a socket directly into a MessagePack
  # unpacker:
  #
  #   unpacker = MessagePack::Unpacker.new
  #   buffer = []
  #   reader = spin do
  #     i.feed_loop(unpacker, :feed_each) { |msg| handle_msg(msg) }
  #   end
  #
  # @param receiver [any] receiver object
  # @param method [Symbol] method to call
  # @param &block [Proc] block to handle result of method call to receiver
  # @return [void]
  def feed_loop(receiver, method = :call, &block)
    Polyphony.backend_recv_feed_loop(self, receiver, method, &block)
  end

  # Sends the given message on the socket.
  #
  # @param mesg [String] data to send
  # @param flags [Integer] send flags
  # @return [Integer] number of bytes sent
  def send(mesg, flags)
    Polyphony.backend_send(self, mesg, flags)
  end

  # Sends one or more strings on the socket. The strings are guaranteed to be
  # written as a single blocking operation.
  #
  # @param *args [Array<String>] string buffers to write
  # @return [Integer] number of bytes written
  def write(*args)
    Polyphony.backend_sendv(self, args, 0)
  end

  # Sends the given message on the socket.
  #
  # @param mesg [String] data to send
  # @return [Integer] number of bytes sent
  def <<(mesg)
    Polyphony.backend_send(self, mesg, 0)
  end

  # call-seq:
  #   socket.readpartial(maxlen) -> string
  #   socket.readpartial(maxlen, buf) -> buf
  #   socket.readpartial(maxlen, buf, buf_pos) -> buf
  #   socket.readpartial(maxlen, buf, buf_pos, raise_on_eof) -> buf
  #
  # Reads up to `maxlen` from the socket. If `buf` is given, it is used as the
  # buffer to read into, otherwise a new string is allocated. If `buf_pos` is
  # given, reads into the given offset (in bytes) in the given buffer. If the
  # given buffer offset is negative, it is calculated from the current end of
  # the buffer (`-1` means the read data will be appended to the end of the
  # buffer). If `raise_on_eof` is `true` (the default,) an `EOFError` will be
  # raised on `EOF`, otherwise `nil` will be returned.
  #
  # If no bytes are available and `EOF` is not hit, this method will block until
  # the socket is ready to read from.
  #
  # @param maxlen [Integer, nil] maximum bytes to read from socket
  # @param buf [String, nil] buffer to read into
  # @param buf_pos [Number] buffer position to read into
  # @param raise_on_eof [bool] whether to raise an exception on `EOF`
  # @return [String, nil] buffer used for reading or nil on `EOF`
  def readpartial(maxlen, str = +'', buffer_pos = 0, raise_on_eof = true)
    result = Polyphony.backend_recv(self, str, maxlen, buffer_pos)
    raise EOFError if !result && raise_on_eof
    result
  end

  # Performs a non-blocking read from the socket of up to `maxlen` bytes. If
  # `buf` is given, it is used as the read buffer, otherwise a new string will
  # be allocated. If the socket is not ready for reading and `exception` is
  # true, an `IO::WaitReadable` will be raised. If the socket is not ready for
  # reading and `exception` is false, `:wait_readable` is returned.
  #
  # @param maxlen [Integer] maximum bytes to read
  # @param buf [String, nil] read buffer
  # @param exception [bool] whether to raise an exception if not ready for reading
  # @return [String, :wait_readable] read buffer
  def read_nonblock(len, str = nil, exception: true)
    @io.read_nonblock(len, str, exception: exception)
  end

  # Performs a non-blocking to the socket. If the socket is not ready for
  # writing and `exception` is true, an `IO::WaitWritable` will be raised. If
  # the socket is not ready for writing and `exception` is false,
  # `:wait_writable` is returned.
  #
  # @param buf [String, nil] write buffer
  # @param exception [bool] whether to raise an exception if not ready for reading
  # @return [Integer, :wait_readable] number of bytes written
  def write_nonblock(buf, exception: true)
    @io.write_nonblock(buf, exception: exception)
  end
end