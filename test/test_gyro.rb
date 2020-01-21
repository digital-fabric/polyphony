# frozen_string_literal: true

require_relative 'helper'

class GyroTest < MiniTest::Test
  def test_fiber_state
    assert_equal :running, Fiber.current.state

    f = Fiber.new {}

    assert_equal :waiting, f.state
    f.resume
    assert_equal :dead, f.state

    f = Fiber.new { }
    f.schedule
    assert_equal :runnable, f.state
    snooze
    assert_equal :dead, f.state
  end

  def test_schedule
    values = []
    fibers = 3.times.map { |i| Fiber.new { values << i } }
    fibers[0].schedule

    assert_equal [], values
    snooze
    assert_equal [0], values
    
    fibers[1].schedule
    fibers[2].schedule

    assert_equal [0], values
    snooze
    assert_equal [0, 1, 2], values
  end

  def test_that_run_loop_returns_immediately_if_no_watchers
    t0 = Time.now
    suspend
    t1 = Time.now
    assert((t1 - t0) < 0.01)
  end

  def test_defer
    values = []
    defer { values << 1 }
    defer { values << 2 }
    defer { values << 3 }
    suspend

    assert_equal [1, 2, 3], values
  end

  def test_schedule
    values = []
    f = Fiber.new do
      values << :foo
      # We *have* to suspend the fiber in order to yield to the reactor,
      # otherwise control will transfer back to root fiber.
      suspend
    end
    assert_equal [], values
    f.schedule
    suspend

    assert_equal [:foo], values
  end

  def test_suspend
    values = []
    Fiber.new do
      values << :foo
      suspend
    end.schedule
    suspend

    assert_equal [:foo], values
  end

  def test_schedule_and_suspend
    values = []
    3.times.map do |i|
      Fiber.new do
        values << i
        suspend
      end.schedule
    end
    suspend

    assert_equal [0, 1, 2], values
  end

  def test_snooze
    values = []
    3.times.map do |i|
      Fiber.new do
        3.times do
          snooze
          values << i
        end
        suspend
      end.schedule
    end
    suspend

    assert_equal [0, 1, 2, 0, 1, 2, 0, 1, 2], values
  end

  def test_break
    skip "break is still not implemented for new scheduler"
    values = []
    Fiber.new do
      values << :foo
      snooze
      # here will never be reached
      values << :bar
      suspend
    end.schedule

    Fiber.new do
      Gyro.break!
    end.schedule

    suspend

    assert_equal [:foo], values
  end

  def test_reset
    values = []
    f1 = Fiber.new do
      values << :foo
      snooze
      values << :bar
      suspend
    end.schedule

    f2 = Fiber.new do
      Thread.current.reset_fiber_scheduling
      values << :restarted
      snooze
      values << :baz
    end.schedule

    suspend

    f1.schedule
    suspend
    assert_equal %i[foo restarted baz], values
  end

  def test_restart
    values = []
    Fiber.new do
      values << :foo
      snooze
      # this part will not be reached, as Gyro state is reset
      values << :bar
      suspend
    end.schedule

    Fiber.new do
      Thread.current.reset_fiber_scheduling

      # control is transfer to the fiber that called Gyro.restart
      values << :restarted
      snooze
      values << :baz
    end.schedule

    suspend

    assert_equal %i[foo restarted baz], values
  end
end
