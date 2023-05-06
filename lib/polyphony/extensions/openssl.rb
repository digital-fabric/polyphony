# frozen_string_literal: true

require 'openssl'
require_relative './socket'

# OpenSSL socket helper methods (to make it compatible with Socket API) and overrides
class ::OpenSSL::SSL::SSLSocket
  # @!visibility private
  def __read_method__
    :readpartial
  end

  # @!visibility private
  alias_method :orig_initialize, :initialize

  # Initializese a new SSL socket
  #
  # @param socket [TCPSocket] socket to wrap
  # @param context [OpenSSL::SSL::SSLContext] optional SSL context
  # @return [void]
  def initialize(socket, context = nil)
    socket = socket.respond_to?(:io) ? socket.io || socket : socket
    context ? orig_initialize(socket, context) : orig_initialize(socket)
  end

  # Sets DONT_LINGER option
  def dont_linger
    io.dont_linger
  end

  # Sets NO_DELAY option
  def no_delay
    io.no_delay
  end

  # Sets REUSE_ADDR option
  def reuse_addr
    io.reuse_addr
  end

  # @!visibility private
  def fill_rbuff
    data = self.sysread(BLOCK_SIZE)
    if data
      @rbuffer << data
    else
      @eof = true
    end
  end

  # @!visibility private
  alias_method :orig_sysread, :sysread

  # @!visibility private
  def sysread(maxlen, buf = +'')
    # ensure socket is non blocking
    Polyphony.backend_verify_blocking_mode(io, false)
    while true
      case (result = sysread_nonblock(maxlen, buf, exception: false))
      when :wait_readable then Polyphony.backend_wait_io(io, false)
      when :wait_writable then Polyphony.backend_wait_io(io, true)
      else return result
      end
    end
  end

  # @!visibility private
  alias_method :orig_syswrite, :syswrite

  # @!visibility private
  def syswrite(buf)
    # ensure socket is non blocking
    Polyphony.backend_verify_blocking_mode(io, false)
    while true
      case (result = write_nonblock(buf, exception: false))
      when :wait_readable then Polyphony.backend_wait_io(io, false)
      when :wait_writable then Polyphony.backend_wait_io(io, true)
      else
        return result
      end
    end
  end

  # @!visibility private
  def flush
    # warn "SSLSocket#flush is not yet implemented in Polyphony"
  end

  # @!visibility private
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
    return readpartial(maxlen, buf, buf_pos) if buf

    buf = +''
    return readpartial(maxlen, buf) if maxlen

    while true
      readpartial(4096, buf, -1)
    end
  rescue EOFError
    buf
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
    if buf_pos != 0
      if (result = sysread(maxlen, +''))
        if buf_pos == -1
          result = buf + result
        else
          result = buf[0...buf_pos] + result
        end
      end
    else
      result = sysread(maxlen, buf)
    end

    raise EOFError if !result && raise_on_eof
    result
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
  # @yield [String] handler block
  # @return [void]
  def read_loop(maxlen = 8192)
    while (data = sysread(maxlen))
      yield data
    end
  end
  alias_method :recv_loop, :read_loop

  # @!visibility private
  alias_method :orig_peeraddr, :peeraddr

  # @!visibility private
  def peeraddr(_ = nil)
    orig_peeraddr
  end
end

# OpenSSL socket helper methods (to make it compatible with Socket API) and overrides
class ::OpenSSL::SSL::SSLServer
  attr_reader :ctx

  # @!visibility private
  alias_method :orig_accept, :accept

  # Accepts a new connection and performs SSL handshake.
  #
  # @return [OpenSSL::SSL::SSLSocket] accepted SSL connection
  def accept
    # when @ctx.servername_cb is set, we use a worker thread to run the
    # ssl.accept call. We need to do this because:
    # - We cannot switch fibers inside of the servername_cb proc (see
    #   https://github.com/ruby/openssl/issues/415)
    # - We don't want to stop the world while we're busy provisioning an ACME
    #   certificate
    if @use_accept_worker.nil?
      if (@use_accept_worker = use_accept_worker_thread?)
        start_accept_worker_thread
      end
    end

    # STDOUT.puts 'SSLServer#accept'
    sock, = @svr.accept
    # STDOUT.puts "- raw sock: #{sock.inspect}"
    begin
      ssl = OpenSSL::SSL::SSLSocket.new(sock, @ctx)
      # STDOUT.puts "- ssl sock: #{ssl.inspect}"
      ssl.sync_close = true
      if @use_accept_worker
        # STDOUT.puts "- send to accept worker"
        @accept_worker_fiber << [ssl, Fiber.current]
        # STDOUT.puts "- wait for accept worker"
        r = receive
        # STDOUT.puts "- got reply from accept worker: #{r.inspect}"
        r.invoke if r.is_a?(Exception)
      else
        ssl.accept
      end
      ssl
    rescue Exception => e
      # STDOUT.puts "- accept exception: #{e.inspect}"
      if ssl
        ssl.close
      else
        sock.close
      end
      raise e
    end
  end

  # @!visibility private
  def start_accept_worker_thread
    fiber = Fiber.current
    @accept_worker_thread = Thread.new do
      fiber << Fiber.current
      loop do
        # STDOUT.puts "- accept_worker wait for work"
        socket, peer = receive
        # STDOUT.puts "- accept_worker got socket from peer #{peer.inspect}"
        socket.accept
        # STDOUT.puts "- accept_worker accept returned"
        peer << socket
        # STDOUT.puts "- accept_worker sent socket back to peer"
      rescue Polyphony::BaseException
        raise
      rescue Exception => e
        # STDOUT.puts "- accept_worker error: #{e}"
        peer << e if peer
      end
    end
    @accept_worker_fiber = receive
  end

  # @!visibility private
  def use_accept_worker_thread?
    !!@ctx.servername_cb
  end

  # @!visibility private
  alias_method :orig_close, :close

  # @!visibility private
  def close
    @accept_worker_thread&.kill
    orig_close
  end

  # call-seq:
  #   socket.accept_loop { |conn| ... }
  #
  # Accepts incoming connections in an infinite loop.
  #
  # @yield [OpenSSL::SSL::SSLSocket] block receiving accepted sockets
  # @return [void]
  def accept_loop(ignore_errors = true)
    loop do
      yield accept
    rescue OpenSSL::SSL::SSLError, SystemCallError => e
      raise e unless ignore_errors
    end
  end
end
