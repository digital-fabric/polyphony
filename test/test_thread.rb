# frozen_string_literal: true

require_relative 'helper'

class ThreadTest < MiniTest::Test
  def test_thread_spin
    buffer = []
    f = spin { (1..3).each { |i| snooze; buffer << i } }
    t = Thread.new do
      s1 = spin { (11..13).each { |i| snooze; buffer << i } }
      s2 = spin { (21..23).each { |i| snooze; buffer << i } }
      Fiber.join(s1, s2)
    end
    f.join
    t.join

    assert_equal [1, 2, 3, 11, 12, 13, 21, 22, 23], buffer.sort
  end

  def test_thread_join
    tr = nil
    # tr = Polyphony::Trace.new(:fiber_all) { |r| p r[:event] }
    # Gyro.trace(true)
    # tr.enable

    buffer = []
    spin { (1..3).each { |i| snooze; buffer << i } }
    t = Thread.new { sleep 0.01; buffer << 4 }

    r = t.join

    assert_equal [1, 2, 3, 4], buffer
    assert_equal t, r
  ensure
    tr&.disable
    Gyro.trace(nil)
  end

  def test_thread_join_with_timeout
    buffer = []
    spin { (1..3).each { |i| snooze; buffer << i } }
    t = Thread.new { sleep 1; buffer << 4 }
    t0 = Time.now
    r = t.join(0.01)

    assert Time.now - t0 < 0.2
    assert_equal [1, 2, 3], buffer
    assert_nil r
  ensure
    # killing the thread will prevent stopping the sleep timer, as well as the
    # thread's event selector, leading to a memory leak.
    t.kill if t.alive?
  end

  def test_thread_inspect
    lineno = __LINE__ + 1
    t = Thread.new {}
    str = format(
      "#<Thread:%d %s:%d (run)>",
      t.object_id,
      __FILE__,
      lineno,
    )
    assert_equal str, t.inspect
  end

  def test_that_suspend_returns_immediately_if_no_watchers
    records = []
    t = Polyphony::Trace.new(:fiber_all) { |r| records << r if r[:event] =~ /^fiber_/ }
    t.enable
    Gyro.trace(true)

    suspend
    t.disable
    assert_equal [:fiber_switchpoint], records.map { |r| r[:event] }
  ensure
    t&.disable
    Gyro.trace(false)
  end

  def test_reset
    values = []
    f1 = spin do
      values << :foo
      snooze
      values << :bar
      suspend
    end

    f2 = spin do
      Thread.current.reset_fiber_scheduling
      values << :restarted
      snooze
      values << :baz
    end

    suspend

    f1.schedule
    suspend
    assert_equal %i[foo restarted baz], values
  end

  def test_restart
    values = []
    spin do
      values << :foo
      snooze
      # this part will not be reached, as Gyro state is reset
      values << :bar
      suspend
    end

    spin do
      Thread.current.reset_fiber_scheduling

      # control is transfer to the fiber that called Gyro.restart
      values << :restarted
      snooze
      values << :baz
    end

    suspend

    assert_equal %i[foo restarted baz], values
  end
end
