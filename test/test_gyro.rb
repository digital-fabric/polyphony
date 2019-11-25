# frozen_string_literal: true

require_relative 'helper'

class RunTest < Minitest::Test
  def test_that_run_loop_returns_immediately_if_no_watchers
    t0 = Time.now
    suspend
    t1 = Time.now
    assert((t1 - t0) < 0.01)
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
    values = []
    Fiber.new do
      values << :foo
      snooze
      # here will never be reached
      values << :bar
      suspend
    end.schedule

    Fiber.new do
      Gyro.break
    end.schedule

    suspend

    assert_equal [:foo], values
  end

  def test_start
    values = []
    f1 = Fiber.new do
      values << :foo
      snooze
      values << :bar
      suspend
    end.schedule

    f2 = Fiber.new do
      Gyro.break
      values << :restarted
      snooze
      values << :baz
    end.schedule

    suspend

    Gyro.start
    f2.schedule
    f1.schedule
    suspend

    assert_equal %i[foo restarted bar baz], values
  end

  def test_restart
    values = []
    Fiber.new do
      values << :foo
      snooze
      # this part will not be reached, as f
      values << :bar
      suspend
    end.schedule

    Fiber.new do
      Gyro.restart

      # control is transfer to the fiber that called Gyro.restart
      values << :restarted
      snooze
      values << :baz
    end.schedule

    suspend

    assert_equal %i[foo restarted baz], values
  end
end
