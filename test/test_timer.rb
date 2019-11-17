# frozen_string_literal: true

require_relative 'helper'

class TimerTest < MiniTest::Test
  def test_that_one_shot_timer_works
    count = 0
    t = Gyro::Timer.new(0.01, 0)
    t.start { count += 1}
    suspend
    assert_equal(1, count)
  end

  def test_that_repeating_timer_works
    count = 0
    t = Gyro::Timer.new(0.001, 0.001)
    t.start { count += 1; t.stop if count >= 3}
    suspend
    assert_equal(3, count)
  end
end
