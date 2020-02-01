# frozen_string_literal: true

require_relative 'helper'

class GyroTest < MiniTest::Test
  def test_break
    skip "break is still not implemented for new scheduler"
    values = []
    Fiber.spin do
      values << :foo
      snooze
      # here will never be reached
      values << :bar
      suspend
    end

    Fiber.spin do
      Gyro.break!
    end

    suspend

    assert_equal [:foo], values
  end
end
