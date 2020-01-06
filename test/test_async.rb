# frozen_string_literal: true

require_relative 'helper'

class AsyncTest < MiniTest::Test
  def test_that_async_watcher_receives_signal_across_threads
    count = 0
    a = Gyro::Async.new
    spin {
      a.await
      count += 1
    }
    snooze
    Thread.new do
      orig_sleep 0.001
      a.signal!
    end
    suspend
    assert_equal(1, count)
  end

  def test_that_async_watcher_coalesces_signals
    count = 0
    a = Gyro::Async.new
    coproc = spin {
      loop {
        a.await
        count += 1
        defer { coproc.stop }
      }
    }
    snooze
    Thread.new do
      orig_sleep 0.001
      3.times { a.signal! }
    end
    coproc.await
    assert_equal(1, count)
  end
end
