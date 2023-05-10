# frozen_string_literal: true

# A Pipe instance represents a UNIX pipe that can be read and written to. This
# API is an alternative to the `IO.pipe` API, that returns two separate fds, one
# for reading and one for writing. Instead, `Polyphony::Pipe` encapsulates the
# two fds in a single object, providing methods that enable us to treat the pipe
# as a normal IO object.
class Polyphony::Pipe
  # @!visibility private
  def __read_method__
    :backend_read
  end

  # @!visibility private
  def __write_method__
    :backend_write
  end

  # Reads a single byte from the pipe.
  #
  # @return [Integer, nil] byte value
  def getbyte
    char = getc
    char ? char.getbyte(0) : nil
  end

  # Reads a single character from the pipe.
  #
  # @return |String, nil] read character
  def getc
    return @read_buffer.slice!(0) if @read_buffer && !@read_buffer.empty?

    @read_buffer ||= +''
    Polyphony.backend_read(self, @read_buffer, 8192, false, -1)
    return @read_buffer.slice!(0) if !@read_buffer.empty?

    nil
  end

  # Reads from the pipe.
  #
  # @param len [Integer, nil] maximum bytes to read
  # @param buf [String, nil] buffer to read into
  # @param buf_pos [Integer] buffer position to read into
  # @return [String] read data
  def read(len = nil, buf = nil, buf_pos = 0)
    if buf
      return Polyphony.backend_read(self, buf, len, true, buf_pos)
    end

    @read_buffer ||= +''
    result = Polyphony.backend_read(self, @read_buffer, len, true, -1)
    return nil unless result

    already_read = @read_buffer
    @read_buffer = +''
    already_read
  end

  # Reads from the pipe.
  #
  # @param len [Integer, nil] maximum bytes to read
  # @param buf [String, nil] buffer to read into
  # @param buf_pos [Integer] buffer position to read into
  # @param raise_on_eof [boolean] whether to raise an error if EOF is detected
  # @return [String] read data
  def readpartial(len, buf = +'', buf_pos = 0, raise_on_eof = true)
    result = Polyphony.backend_read(self, buf, len, false, buf_pos)
    raise EOFError if !result && raise_on_eof

    result
  end

  # Writes to the pipe.
  
  # @param buf [String] data to write
  # @param args [any] further arguments to pass to Polyphony.backend_write
  # @return [Integer] bytes written
  def write(buf, *args)
    Polyphony.backend_write(self, buf, *args)
  end

  # Writes to the pipe.
  
  # @param buf [String] data to write
  # @return [Integer] bytes written
  def <<(buf)
    Polyphony.backend_write(self, buf)
    self
  end

  # @param sep [String] line separator
  # @param _limit [Integer, nil] line length limit
  # @param _chomp [boolean, nil] whether to chomp the read line
  # @return [String, nil] read line
  def gets(sep = $/, _limit = nil, _chomp: nil)
    if sep.is_a?(Integer)
      sep = $/
      _limit = sep
    end
    sep_size = sep.bytesize

    @read_buffer ||= +''

    while true
      idx = @read_buffer.index(sep)
      return @read_buffer.slice!(0, idx + sep_size) if idx

      result = readpartial(8192, @read_buffer, -1)
      return nil unless result
    end
  rescue EOFError
    return nil
  end

  # def print(*args)
  # end

  # def printf(format, *args)
  # end

  # def putc(obj)
  # end

  # @!visibility private
  LINEFEED = "\n"
  # @!visibility private
  LINEFEED_RE = /\n$/.freeze

  # Writes a line with line feed to the pipe.
  # 
  # @param args [Array] zero or more lines
  def puts(*args)
    if args.empty?
      write LINEFEED
      return
    end

    idx = 0
    while idx < args.size
      arg = args[idx]
      args[idx] = arg = arg.to_s unless arg.is_a?(String)
      if arg =~ LINEFEED_RE
        idx += 1
      else
        args.insert(idx + 1, LINEFEED)
        idx += 2
      end
    end

    write(*args)
    nil
  end

  # def readbyte
  # end

  # def readchar
  # end

  # def readline(sep = $/, limit = nil, chomp: nil)
  # end

  # def readlines(sep = $/, limit = nil, chomp: nil)
  # end

  # @!visibility private
  def write_nonblock(string, _options = {})
    write(string)
  end

  # @!visibility private
  def read_nonblock(maxlen, buf = nil, _options = nil)
    buf ? readpartial(maxlen, buf) : readpartial(maxlen)
  end

  # Runs a read loop.
  #
  # @param maxlen [Integer] maximum bytes to read
  # @yield [String] read data
  # @return [void]
  def read_loop(maxlen = 8192, &block)
    Polyphony.backend_read_loop(self, maxlen, &block)
  end

  # Receives data from the pipe in an infinite loop, passing the data to the
  # given receiver using the given method. If a block is given, the result of
  # the method call to the receiver is passed to the block.
  #
  # This method can be used to feed data into parser objects. The following
  # example shows how to feed data from a pipe directly into a MessagePack
  # unpacker:
  #
  #   unpacker = MessagePack::Unpacker.new
  #   buffer = []
  #   reader = spin do
  #     pipe.feed_loop(unpacker, :feed_each) { |msg| handle_msg(msg) }
  #   end
  #
  # @param receiver [any] receiver object
  # @param method [Symbol] method to call
  # @return [void]
  def feed_loop(receiver, method = :call, &block)
    Polyphony.backend_feed_loop(self, receiver, method, &block)
  end

  # Waits for pipe to become readable.
  #
  # @param timeout [Number, nil] optional timeout in seconds
  # @return [Polyphony::Pipe] self
  def wait_readable(timeout = nil)
    if timeout
      move_on_after(timeout) do
        Polyphony.backend_wait_io(self, false)
        self
      end
    else
      Polyphony.backend_wait_io(self, false)
      self
    end
  end

  # Waits for pipe to become writeable.
  #
  # @param timeout [Number, nil] optional timeout in seconds
  # @return [Polyphony::Pipe] self
  def wait_writable(timeout = nil)
    if timeout
      move_on_after(timeout) do
        Polyphony.backend_wait_io(self, true)
        self
      end
    else
      Polyphony.backend_wait_io(self, true)
      self
    end
  end

  # Splices to the pipe from the given source.
  #
  # @param src [IO] source to splice from
  # @param maxlen [Integer] maximum bytes to splice
  # @return [Integer] bytes spliced
  def splice_from(src, maxlen)
    Polyphony.backend_splice(src, self, maxlen)
  end

  if RUBY_PLATFORM =~ /linux/
    # Tees to the pipe from the given source.
    #
    # @param src [IO] source to tee from
    # @param maxlen [Integer] maximum bytes to tee
    # @return [Integer] bytes teed
    def tee_from(src, maxlen)
      Polyphony.backend_tee(src, self, maxlen)
    end
  end
end
