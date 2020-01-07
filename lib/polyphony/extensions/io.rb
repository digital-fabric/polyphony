# frozen_string_literal: true

require 'open3'

# IO overrides
class ::IO
  class << self
    alias_method :orig_binread, :binread
    def binread(name, length = nil, offset = nil)
      File.open(name, 'rb:ASCII-8BIT') do |f|
        f.seek(offset) if offset
        length ? f.read(length) : f.read
      end
    end

    alias_method :orig_binwrite, :binwrite
    def binwrite(name, string, offset = nil)
      File.open(name, 'wb:ASCII-8BIT') do |f|
        f.seek(offset) if offset
        f.write(string)
      end
    end

    EMPTY_HASH = {}.freeze

    alias_method :orig_foreach, :foreach
    def foreach(name, sep = $/, limit = nil, getline_args = EMPTY_HASH, &block)
      # IO.orig_read(name).each_line(&block)
      raise NotImplementedError

      # if sep.is_a?(Integer)
      #   sep = $/
      #   limit = sep
      # end
      # File.open(name, 'r') do |f|
      #   f.each_line(sep, limit, getline_args, &block)
      # end
    end

    alias_method :orig_read, :read
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

    # alias_method :orig_readlines, :readlines
    # def readlines(name, sep = $/, limit = nil, getline_args = EMPTY_HASH)
    #   File.open(name, 'r') do |f|
    #     f.readlines(sep, limit, getline_args)
    #   end
    # end

    alias_method :orig_write, :write
    def write(name, string, offset = nil, opt = EMPTY_HASH)
      File.open(name, opt[:mode] || 'w') do |f|
        f.seek(offset) if offset
        f.write(string)
      end
    end

    alias_method :orig_popen, :popen
    def popen(cmd, mode = 'r')
      return orig_popen(cmd, mode) unless block_given?

      Open3.popen2(cmd) { |_i, o, _t| yield o }
    end
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

  # def getbyte
  # end

  # def getc
  # end

  alias_method :orig_gets, :gets
  def gets(sep = $/, _limit = nil, _chomp: nil)
    if sep.is_a?(Integer)
      sep = $/
      _limit = sep
    end
    sep_size = sep.bytesize

    @gets_buffer ||= +''

    loop do
      idx = @gets_buffer.index(sep)
      return @gets_buffer.slice!(0, idx + sep_size) if idx

      if (data = readpartial(8192))
        @gets_buffer << data
      else
        return nil if @gets_buffer.empty?

        line = @gets_buffer.freeze
        @gets_buffer = +''
        return line
      end
    end
    # orig_gets(sep, limit, chomp: chomp)
  end

  # def print(*args)
  # end

  # def printf(format, *args)
  # end

  # def putc(obj)
  # end

  alias_method :orig_puts, :puts
  def puts(*args)
    if args.empty?
      write "\n"
      return
    end

    s = args.each_with_object(+'') do |a, str|
      if a.is_a?(Array)
        a.each { |a2| str << a2.to_s << "\n" }
      else
        a = a.to_s
        str << a
        str << "\n" unless a =~ /\n$/
      end
    end
    write s
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

  alias_method :orig_write_nonblock, :write_nonblock
  def write_nonblock(string, _options = {})
    # STDOUT << '>'
    write(string, 0)
  end

  alias_method :orig_read_nonblock, :read_nonblock
  def read_nonblock(maxlen, buf = nil, _options = nil)
    # STDOUT << '<'
    buf ? readpartial(maxlen, buf) : readpartial(maxlen)
  end
end
