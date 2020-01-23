# frozen_string_literal: true

require_relative 'helper'

class ThreadTest < MiniTest::Test
  def test_thread_spin
    buffer = []
    spin { (1..3).each { |i| snooze; buffer << i } }
    t = Thread.new do
      s1 = spin { (11..13).each { |i| snooze; buffer << i } }
      s2 = spin { (21..23).each { |i| snooze; buffer << i } }
      Fiber.join(s1, s2)
    end
    t.join

    assert_equal [1, 2, 3, 11, 12, 13, 21, 22, 23], buffer.sort
  end

  def test_thread_join
    buffer = []
    spin { (1..3).each { |i| snooze; buffer << i } }
    t = Thread.new { sleep 0.01; buffer << 4 }
    r = t.join

    assert_equal [1, 2, 3, 4], buffer
    assert_equal t, r
  end

  def test_thread_join_with_timeout
    buffer = []
    spin { (1..3).each { |i| snooze; buffer << i } }
    t = Thread.new { sleep 1; buffer << 4 }
    t0 = Time.now
    r = t.join(0.02)
    t1 = Time.now

    assert t1 - t0 >= 0.02
    assert t1 - t0 < 0.04
    assert_equal [1, 2, 3], buffer
    assert_nil r
  ensure
    # killing the thread will prevent stopping the sleep timer, as well as the
    # thread's event selector, leading to a memory leak.
    t.kill if t.alive?
  end
end
