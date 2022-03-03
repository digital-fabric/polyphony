# frozen_string_literal: true

require_relative 'helper'
require 'msgpack'

class RawBufferTest < MiniTest::Test
  def test_with_raw_buffer
    result = Polyphony.__with_raw_buffer__(64) do |b|
      assert_kind_of Integer, b
      assert_equal 64, Polyphony.__raw_buffer_size__(b)
      :foo
    end
    assert_equal :foo, result
  end

  def test_raw_buffer_get_set
    Polyphony.__with_raw_buffer__(64) do |b|
      # should raise if buffer not big enough
      assert_raises { Polyphony.__raw_buffer_set__(b, '*' * 65) }

      Polyphony.__raw_buffer_set__(b, 'foobar')
      assert_equal 6, Polyphony.__raw_buffer_size__(b)

      str = Polyphony.__raw_buffer_get__(b)
      assert_equal 'foobar', str

      str = Polyphony.__raw_buffer_get__(b, 3)
      assert_equal 'foo', str

      Polyphony.__raw_buffer_set__(b, '')
      assert_equal 0, Polyphony.__raw_buffer_size__(b)

      str = Polyphony.__raw_buffer_get__(b)
      assert_equal '', str
    end
  end
end
