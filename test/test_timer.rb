# frozen_string_literal: true

require_relative 'helper'

class TimerTest < MiniTest::Test
  def test_that_one_shot_timer_works
    count = 0
    t = Gyro::Timer.new(0.01, 0)
    spin {
      t.await
      count += 1
    }
    suspend
    assert_equal 1, count
  end

  def test_that_repeating_timer_works
    count = 0
    t = Gyro::Timer.new(0.001, 0.001)
    spin {
      loop {
        t.await
        count += 1
        break if count >= 3
      }
    }
    suspend
    assert_equal 3, count
  end

  def test_that_repeating_timer_compensates_for_drift
    count = 0
    t = Gyro::Timer.new(0.01, 0.01)
    times = []
    last = nil
    spin {
      last = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
      loop {
        t.await
        times << ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
        count += 1
        sleep 0.005
        break if count >= 10
      }
    }
    suspend
    deltas = times.each_with_object([]) { |t, a| a << t - last; last = t }
    assert_equal 0, deltas.filter { |d| (d - 0.01).abs >= 0.006 }.size
  end
end
