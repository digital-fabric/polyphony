# frozen_string_literal: true

require_relative 'helper'

class AsyncTest < MiniTest::Test
  def test_that_async_watcher_receives_signal_across_threads
    count = 0
    a = Gyro::Async.new { count += 1; a.stop }
    Thread.new { sync_sleep 0.001; a.signal! }
    suspend
    assert_equal(1, count)
  end

  def test_that_async_watcher_coalesces_signals
    count = 0
    a = Gyro::Async.new do
      count += 1
      Gyro::Timer.new(0.01, 0).start { a.stop }
    end
    Thread.new do
      sync_sleep 0.001
      3.times { a.signal! }
    end
    suspend
    assert_equal(1, count)
  end
end