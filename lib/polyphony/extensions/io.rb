# frozen_string_literal: true

require 'open3'

# IO extensions
class ::IO
  class << self
    # @!visibility private
    alias_method :orig_binread, :binread

    # @!visibility private
    def binread(name, length = nil, offset = nil)
      File.open(name, 'rb:ASCII-8BIT') do |f|
        f.seek(offset) if offset
        length ? f.read(length) : f.read
      end
    end

    # @!visibility private
    alias_method :orig_binwrite, :binwrite

    # @!visibility private
    def binwrite(name, string, offset = nil)
      File.open(name, 'wb:ASCII-8BIT') do |f|
        f.seek(offset) if offset
        f.write(string)
      end
    end

    # @!visibility private
    EMPTY_HASH = {}.freeze

    # @!visibility private
    alias_method :orig_foreach, :foreach

    # @!visibility private
    def foreach(name, sep = $/, limit = nil, getline_args = EMPTY_HASH, &block)
      if sep.is_a?(Integer)
        sep = $/
        limit = sep
      end
      File.open(name, 'r') do |f|
        f.each_line(sep, limit, chomp: getline_args[:chomp], &block)
      end
    end

    # @!visibility private
    alias_method :orig_read, :read

    # @!visibility private
    def read(name, length = nil, offset = nil, opt = EMPTY_HASH)
      if length.is_a?(Hash)
        opt = length
        length = nil
      end
      File.open(name, opt[:mode] || 'r') do |f|
        f.seek(offset) if offset
        length ? f.read(length) : f.read
      end
    end

    alias_method :orig_readlines, :readlines
    def readlines(name, sep = $/, limit = nil, getline_args = EMPTY_HASH)
      File.open(name, 'r') do |f|
        f.readlines(sep, **getline_args)
      end
    end

    # @!visibility private
    alias_method :orig_write, :write

    # @!visibility private
    def write(name, string, offset = nil, opt = EMPTY_HASH)
      File.open(name, opt[:mode] || 'w') do |f|
        f.seek(offset) if offset
        f.write(string)
      end
    end

    # @!visibility private
    alias_method :orig_popen, :popen

    # @!visibility private
    def popen(cmd, mode = 'r')
      return orig_popen(cmd, mode) unless block_given?

      Open3.popen2(cmd) { |_i, o, _t| yield o }
    end

    def copy_stream(src, dst, src_length = nil, src_offset = 0)
      close_src = false
      close_dst = false
      if !src.respond_to?(:readpartial)
        src = File.open(src, 'r+')
        close_src = true
      end
      if !dst.respond_to?(:readpartial)
        dst = File.open(dst, 'w+')
        close_dst = true
      end
      src.seek(src_offset) if src_offset > 0

      pipe = Polyphony::Pipe.new

      pipe_to_dst = spin { dst.splice_from(pipe, -65536) }

      count = 0
      if src_length
        while count < src_length
          count += pipe.splice_from(src, src_length)
        end
      else
        count = pipe.splice_from(src, -65536)
      end
      
      pipe.close
      pipe_to_dst.await
      
      count
    ensure
      pipe_to_dst&.stop
      src.close if close_src
      dst.close if close_dst
    end

    # Splices from one IO to another IO. At least one of the IOs must be a pipe.
    # If maxlen is negative, splices repeatedly using absolute value of maxlen
    # until EOF is encountered.
    #
    # @param src [IO, Polyphony::Pipe] source to splice from
    # @param dest [IO, Polyphony::Pipe] destination to splice to
    # @param maxlen [Integer] maximum bytes to splice
    # @return [Integer] bytes spliced
    def splice(src, dest, maxlen)
      Polyphony.backend_splice(src, dest, maxlen)
    end

    # Creates a pipe and splices data between the two given IOs, using the pipe,
    # splicing until EOF.
    #
    # @param src [IO, Polyphony::Pipe] source to splice from
    # @param dest [IO, Polyphony::Pipe] destination to splice to
    # @return [Integer] total bytes spliced
    def double_splice(src, dest)
      Polyphony.backend_double_splice(src, dest)
    end

    if !Polyphony.respond_to?(:backend_double_splice)
      def double_splice(src, dest)
        pipe = Polyphony::Pipe.new
        f = spin { Polyphony.backend_splice(pipe, dest, -65536) }
        Polyphony.backend_splice(src, pipe, -65536)
        pipe.close
      ensure
        f.stop
      end
    end

    # Tees data from the source to the desination.
    #
    # @param src [IO, Polyphony::Pipe] source to tee from
    # @param dest [IO, Polyphony::Pipe] destination to tee to
    # @param maxlen [Integer] maximum bytes to tee
    # @return [Integer] total bytes teed
    def tee(src, dest, maxlen)
      Polyphony.backend_tee(src, dest, maxlen)
    end

    if RUBY_PLATFORM !~ /linux/
      # @!visibility private
      def double_splice(src, dest)
        raise NotImplementedError
      end

      # @!visibility private
      def tee(src, dest, maxlen)
        raise NotImplementedError
      end
    end
  end
end

# IO instance method patches
class ::IO
  # @!visibility private
  def __read_method__
    :backend_read
  end

  # @!visibility private
  def __write_method__
    :backend_write
  end

  # def each(sep = $/, limit = nil, chomp: nil)
  #   sep, limit = $/, sep if sep.is_a?(Integer)
  # end
  # alias_method :each_line, :each

  # def each_byte
  # end

  # def each_char
  # end

  # def each_codepoint
  # end

  # @!visibility private
  alias_method :orig_getbyte, :getbyte

  # @!visibility private
  def getbyte
    char = getc
    char&.getbyte(0)
  end

  # @!visibility private
  alias_method :orig_getc, :getc

  # @!visibility private
  def getc
    return @read_buffer.slice!(0) if @read_buffer && !@read_buffer.empty?

    @read_buffer ||= +''
    Polyphony.backend_read(self, @read_buffer, 8192, false, -1)
    return @read_buffer.slice!(0) if !@read_buffer.empty?

    nil
  end

  # @!visibility private
  def ungetc(chr)
    chr = chr.chr if chr.is_a?(Integer)
    if @read_buffer
      @read_buffer.prepend(chr)
    else
      @read_buffer = +chr
    end
  end
  alias_method :ungetbyte, :ungetc

  # @!visibility private
  alias_method :orig_read, :read

  # @!visibility private
  def read(len = nil, buf = nil, buffer_pos = 0)
    return '' if len == 0
    return Polyphony.backend_read(self, buf, len, true, buffer_pos) if buf

    @read_buffer ||= +''
    result = Polyphony.backend_read(self, @read_buffer, len, true, -1)
    return '' unless result

    already_read = @read_buffer
    @read_buffer = +''
    already_read
  end

  # @!visibility private
  alias_method :orig_readpartial, :read

  # @!visibility private
  def readpartial(len, str = +'', buffer_pos = 0, raise_on_eof = true)
    result = Polyphony.backend_read(self, str, len, false, buffer_pos)
    raise EOFError if !result && raise_on_eof

    result
  end

  # @!visibility private
  alias_method :orig_write, :write

  # @!visibility private
  def write(str, *args)
    Polyphony.backend_write(self, str, *args)
  end

  # @!visibility private
  alias_method :orig_write_chevron, :<<

  # @!visibility private
  def <<(str)
    Polyphony.backend_write(self, str)
    self
  end

  # @!visibility private
  alias_method :orig_gets, :gets

  # @!visibility private
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

  # @!visibility private
  def each_line(sep = $/, limit = nil, chomp: false)
    if sep.is_a?(Integer)
      limit = sep
      sep = $/
    end
    sep_size = sep.bytesize


    @read_buffer ||= +''

    while true
      while (idx = @read_buffer.index(sep))
        line = @read_buffer.slice!(0, idx + sep_size)
        line = line.chomp if chomp
        yield line
      end

      result = Polyphony.backend_read(self, @read_buffer, 8192, false, -1)
      return self if !result
    end
  rescue EOFError
    return self
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
  LINEFEED_RE = /\n$/

  # @!visibility private
  alias_method :orig_puts, :puts

  # @!visibility private
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
  alias_method :orig_write_nonblock, :write_nonblock

  # @!visibility private
  def write_nonblock(string, _options = {})
    write(string)
  end

  # @!visibility private
  alias_method :orig_read_nonblock, :read_nonblock

  # @!visibility private
  def read_nonblock(maxlen, buf = nil, _options = nil)
    buf ? readpartial(maxlen, buf) : readpartial(maxlen)
  end

  # Reads up to `maxlen` bytes at a time in an infinite loop. Read data
  # will be passed to the given block.
  #
  # @param maxlen [Integer] maximum bytes to receive
  # @yield [String] read data
  # @return [IO] self
  def read_loop(maxlen = 8192, &block)
    Polyphony.backend_read_loop(self, maxlen, &block)
  end

  # Receives data from the io in an infinite loop, passing the data to the given
  # receiver using the given method. If a block is given, the result of the
  # method call to the receiver is passed to the block.
  #
  # This method can be used to feed data into parser objects. The following
  # example shows how to feed data from a io directly into a MessagePack
  # unpacker:
  #
  #   unpacker = MessagePack::Unpacker.new
  #   io.feed_loop(unpacker, :feed_each) { |msg| handle_msg(msg) }
  #
  # @param receiver [any] receiver object
  # @param method [Symbol] method to call
  # @return [IO] self
  def feed_loop(receiver, method = :call, &block)
    Polyphony.backend_feed_loop(self, receiver, method, &block)
  end

  # Waits for the IO to become readable, with an optional timeout.
  #
  # @param timeout [Integer, nil] optional timeout in seconds.
  # @return [IO] self
  def wait_readable(timeout = nil)
    return self if @read_buffer && !@read_buffer.empty?

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

  # Waits for the IO to become writeable, with an optional timeout.
  #
  # @param timeout [Integer, nil] optional timeout in seconds.
  # @return [IO] self
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

  # Splices data from the given IO. If maxlen is negative, splices repeatedly
  # using absolute value of maxlen until EOF is encountered.
  #
  # @param src [IO, Polpyhony::Pipe] source to splice from
  # @param maxlen [Integer] maximum bytes to splice
  # @return [Integer] bytes spliced
  def splice_from(src, maxlen)
    Polyphony.backend_splice(src, self, maxlen)
  end

  # @!visibility private
  alias_method :orig_close, :close

  # Closes the IO instance
  #
  # @return [void]
  def close
    return if closed?

    Polyphony.backend_close(self) rescue nil
    nil
  end

  if RUBY_PLATFORM =~ /linux/
    # Tees data from the given IO.
    #
    # @param src [IO, Polpyhony::Pipe] source to tee from
    # @param maxlen [Integer] maximum bytes to tee
    # @return [Integer] bytes teed
    def tee_from(src, maxlen)
      Polyphony.backend_tee(src, self, maxlen)
    end
  end
end
