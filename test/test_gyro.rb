# frozen_string_literal: true

require_relative 'helper'

class GyroTest < MiniTest::Test
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
end
