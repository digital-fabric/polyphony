# frozen_string_literal: true

class ::IO
  def read_watcher
    @read_watcher ||= EV::IO.new(self, :r)
  end

  def write_watcher
    @write_watcher ||= EV::IO.new(self, :w)
  end

  def stop_watchers
    @read_watcher&.stop
    @write_watcher&.stop
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

  # def gets(sep = $/, limit = nil, chomp: nil)
  #   sep, limit = $/, sep if sep.is_a?(Integer)
  # end

  # def print(*args)
  # end

  # def printf(format, *args)
  # end

  # def putc(obj)
  # end

  # def puts(*args)
  # end

  # def readbyte
  # end

  # def readchar
  # end

  # def readline(sep = $/, limit = nil, chomp: nil)
  # end

  # def readlines(sep = $/, limit = nil, chomp: nil)
  # end
end