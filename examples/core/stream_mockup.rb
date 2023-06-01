# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

class Stream
  def initialize(io)
    @io = io
    @buffer = +''
    @length = 0
    @pos = 0
  end

  def getbyte
    if @pos == @length
      return nil if !fill_buffer
    end
    byte = @buffer[@pos].getbyte(0)
    @pos += 1
    byte
  end

  def getc
    if @pos == @length
      return nil if !fill_buffer
    end
    char = @buffer[@pos]
    @pos += 1
    char
  end

  def ungetc(c)
    @buffer.insert(@pos, c)
    @length += 1
    c
  end

  def gets
  end

  def read
  end

  def readpartial
  end

  private

  def fill_buffer
    Polyphony.backend_read(@io, @buffer, 8192, false, -1)
    @length = @buffer.size
  end
end

i, o = IO.pipe
s = Stream.new(i)

f = spin do
  loop do
    b = s.getbyte
    p getbyte: b
    s.ungetc(b.to_s) if rand > 0.5
  end
end

o << 'hello'
sleep 0.1

