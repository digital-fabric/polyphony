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
    t = Gyro::Timer.new(0.1, 0.1)
    deltas = []
    last = nil
    spin {
      last = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
      loop {
        t.await
        now = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
        elapsed = (now - last)
        deltas << elapsed
        last = now
        count += 1
        sleep 0.05
        break if count >= 3
      }
    }
    suspend
    assert_equal 0, deltas[1..-1].filter { |d| (d - 0.1).abs >= 0.05 }.size
  end
end
