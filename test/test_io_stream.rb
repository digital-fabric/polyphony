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
    p = Polyphony.pipe
    s = Polyphony::IOStream.new(p)

    p << 'abc'
    p.close

    assert_equal 97, s.getbyte
    assert_equal 98, s.getbyte
    assert_equal 99, s.getbyte
    assert_nil s.getbyte
  end

  def test_getc
    p = Polyphony.pipe
    s = Polyphony::IOStream.new(p)
    
    p << 'abc'
    p.close

    assert_equal 'a', s.getc
    assert_equal 'b', s.getc
    assert_equal 'c', s.getc
    assert_nil s.getc
  end

  def test_blocking_getc_with_exception
    p = Polyphony.pipe
    s = Polyphony::IOStream.new(p)

    buffer_status = Polyphony.buffer_manager_status;

    assert_equal 0, s.left
    assert_equal [0], buffer_status.values.uniq

    main_f = Fiber.current
    f = spin do
      main_f << :ready
      s.getc
    end

    assert_equal :ready, receive
    snooze
    f.stop(:done)
    c = f.await

    assert_equal :done, c
    assert_equal 0, s.left
    assert_equal [0], buffer_status.values.uniq
  end
end
