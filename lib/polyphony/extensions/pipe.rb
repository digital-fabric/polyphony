# frozen_string_literal: true

# Pipe instance methods
class Polyphony::Pipe
  def __read_method__
    :backend_read
  end

  def getbyte
    char = getc
    char ? char.getbyte(0) : nil
  end

  def getc
    return @read_buffer.slice!(0) if @read_buffer && !@read_buffer.empty?

    @read_buffer ||= +''
    Polyphony.backend_read(self, @read_buffer, 8192, false, -1)
    return @read_buffer.slice!(0) if !@read_buffer.empty?

    nil
  end

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

  def readpartial(len, str = +'', buffer_pos = 0, raise_on_eof = true)
    result = Polyphony.backend_read(self, str, len, false, buffer_pos)
    raise EOFError if !result && raise_on_eof

    result
  end

  def write(str, *args)
    Polyphony.backend_write(self, str, *args)
  end

  def <<(str)
    Polyphony.backend_write(self, str)
    self
  end

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

  LINEFEED = "\n"
  LINEFEED_RE = /\n$/.freeze

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

  def write_nonblock(string, _options = {})
    write(string)
  end

  def read_nonblock(maxlen, buf = nil, _options = nil)
    buf ? readpartial(maxlen, buf) : readpartial(maxlen)
  end

  def read_loop(maxlen = 8192, &block)
    Polyphony.backend_read_loop(self, maxlen, &block)
  end

  def feed_loop(receiver, method = :call, &block)
    Polyphony.backend_feed_loop(self, receiver, method, &block)
  end

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

  def splice_from(src, maxlen)
    Polyphony.backend_splice(src, self, maxlen)
  end

  def splice_to_eof_from(src, chunksize = 8192)
    Polyphony.backend_splice_to_eof(src, self, chunksize)
  end

  def tee_from(src, maxlen)
    Polyphony.backend_tee(src, self, maxlen)
  end
end
