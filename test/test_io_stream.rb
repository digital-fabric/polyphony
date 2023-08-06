# frozen_string_literal: true

require_relative 'helper'

class IOStreamTest < MiniTest::Test
  def test_left
    s = Polyphony::IOStream.new(nil)
    
    assert_equal 0, s.left

    s << 'abc'
    s << 'def'

    assert_equal 6, s.left
  end

  def test_getbyte
    s = Polyphony::IOStream.new(nil)
    
    assert_nil s.getbyte

    s << 'abc'

    assert_equal 97, s.getbyte
    assert_equal 98, s.getbyte
    assert_equal 99, s.getbyte
    assert_nil s.getbyte
  end

  def test_getc
    s = Polyphony::IOStream.new(nil)
    
    assert_nil s.getc

    s << 'abc'

    assert_equal 'a', s.getc
    assert_equal 'b', s.getc
    assert_equal 'c', s.getc
    assert_nil s.getc
  end
end
