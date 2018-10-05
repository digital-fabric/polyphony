require 'minitest/autorun'
require 'modulation'

Core = import('../lib/nuclear/core')

module EVTest
  class RunTest < Minitest::Test
    def test_that_run_loop_returns_immediately_if_no_watchers
      t0 = Time.now
      EV.run
      t1 = Time.now
      assert (t1 - t0) < 0.001
    end
  end

  class TimerTest < MiniTest::Test
    def test_that_one_shot_timer_works
      count = 0
      t = EV::Timer.new(0.01, 0) { count += 1}
      EV.run
      assert_equal(1, count)
    end

    def test_that_timeout_api_works
      count = 0
      t = Core.timeout(0.001) { count += 1 }
      assert_kind_of(EV::Timer, t)
      EV.run
      assert_equal(1, count)
    end

    def test_that_repeating_timer_works
      count = 0
      t = EV::Timer.new(0.001, 0.001) { count += 1; t.stop if count >= 3}
      EV.run
      assert_equal(3, count)
    end

    def test_that_interval_api_works
      count = 0
      t = Core.interval(0.001) { count += 1; t.stop if count >= 3 }
      assert_kind_of(EV::Timer, t)
      EV.run
      assert_equal(3, count)
    end
  end

  class IOTest < MiniTest::Test
    def test_that_reading_works
      i, o = IO.pipe
      data = +''
      w = EV::IO.new(i, :r, true) do
        i.read_nonblock(8192, data)
        w.stop unless data.empty?
      end
      EV::Timer.new(0, 0) { o << 'hello' }
      EV.run
      assert_equal('hello', data)
    end
  end

  class SignalTest < MiniTest::Test
    def test_that_signal_watcher_receives_signal
      sig = Signal.list['USR1']
      count = 0
      w = EV::Signal.new(sig) { count += 1; w.stop }
      Thread.new { sleep 0.001; Process.kill(:USR1, Process.pid) }
      EV.run
      assert_equal(1, count)
    end

    def test_that_signal_watcher_receives_signal
      count = 0
      w = Core.trap(:usr1) { count += 1; w.stop }
      assert_kind_of(EV::Signal, w)
      Thread.new { sleep 0.001; Process.kill(:USR1, Process.pid) }
      EV.run
      assert_equal(1, count)
    end
  end

  class AsyncTest < MiniTest::Test
    def test_that_async_watcher_receives_signal_across_threads
      count = 0
      a = EV::Async.new { count += 1; a.stop }
      Thread.new { sleep 0.001; a.signal! }
      EV.run
      assert_equal(1, count)
    end

    def test_that_async_watcher_coalesces_signals
      count = 0
      a = EV::Async.new { count += 1 }
      Core.timeout(0.01) { a.stop }
      Thread.new { sleep 0.001; 3.times { a.signal! } }
      EV.run
      assert_equal(1, count)
    end
  end
end