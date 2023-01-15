# frozen_string_literal: true

require_relative 'helper'

class EnumeratorTest < MiniTest::Test
  def test_each_enumerator
    o = [1, 2, 3]
    e = o.each

    r = []
    loop do
      r << e.next
    rescue StopIteration
      break
    end

    assert_equal o, r
  end

  def test_custom_io_enumerator
    i, o = IO.pipe

    spin do
      10.times { o.puts 'foo' }
      o.close
    end

    e_fiber = nil
    e = Enumerator.new do |y|
      e_fiber ||= Fiber.current
      while (l = i.gets)
        y << l
      end
    end

    r = []
    loop do
      r << e.next
    rescue StopIteration
      break
    end

    assert_equal ["foo\n"] * 10, r
    assert Fiber.current != e_fiber
  end
end
