# frozen_string_literal: true

require_relative 'helper'

class RunTest < Minitest::Test
  def test_that_run_loop_returns_immediately_if_no_watchers
    t0 = Time.now
    suspend
    t1 = Time.now
    assert (t1 - t0) < 0.001
  end
end

class IdleTest < MiniTest::Test
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
    f = Fiber.new {
      values << :foo
      # We *have* to suspend the fiber in order to yield to the reactor,
      # otherwise control will transfer back to main fiber.
      suspend
    }
    assert_equal [], values
    f.schedule
    suspend

    assert_equal [:foo], values
  end

  def test_suspend
    values = []
    Fiber.new {
      values << :foo
      suspend
    }.schedule
    suspend

    assert_equal [:foo], values
  end

  def test_schedule_and_suspend
    values = []
    fibers = 3.times.map { |i| 
      Fiber.new {
        values << i
        suspend
      }.schedule
    }
    suspend

    assert_equal [0, 1, 2], values
  end

  def test_snooze
    values = []
    fibers = 3.times.map { |i|
      Fiber.new {
        3.times { snooze; values << i }
        suspend
      }.schedule
    }
    suspend

    assert_equal [0, 1, 2, 0, 1, 2, 0, 1, 2], values
  end

  def test_break
    values = []
    Fiber.new {
      values << :foo
      snooze
      # here will never be reached
      values << :bar
      suspend
    }.schedule
    
    Fiber.new {
      Gyro.break
    }.schedule

    suspend

    assert_equal [:foo], values
  end

  def test_start
    values = []
    f1 = Fiber.new {
      values << :foo
      snooze
      values << :bar
      suspend
    }.schedule
    
    f2 = Fiber.new {
      Gyro.break
      values << :restarted
      snooze
      values << :baz
    }.schedule

    suspend
    
    Gyro.start
    f2.schedule
    f1.schedule
    suspend

    assert_equal [:foo, :restarted, :bar, :baz], values
  end

  def test_restart
    values = []
    Fiber.new {
      values << :foo
      snooze
      # this part will not be reached, as f
      values << :bar
      suspend
    }.schedule
    
    Fiber.new {
      Gyro.restart

      # control is transfer to the fiber that called Gyro.restart
      values << :restarted
      snooze
      values << :baz
    }.schedule

    suspend

    assert_equal [:foo, :restarted, :baz], values
  end
end
