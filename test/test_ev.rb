require 'minitest/autorun'
require 'bundler/setup'
require 'polyphony'

class EVRunTest < Minitest::Test
  def setup
    EV.rerun
  end

  def test_that_run_loop_returns_immediately_if_no_watchers
    t0 = Time.now
    suspend
    t1 = Time.now
    assert (t1 - t0) < 0.001
  end
end

class EVTimerTest < MiniTest::Test
  def setup
    EV.rerun
  end

  def test_that_one_shot_timer_works
    count = 0
    t = EV::Timer.new(0.01, 0)
    t.start { count += 1}
    suspend
    assert_equal(1, count)
  end

  def test_that_repeating_timer_works
    count = 0
    t = EV::Timer.new(0.001, 0.001)
    t.start { count += 1; t.stop if count >= 3}
    suspend
    assert_equal(3, count)
  end
end

class EVIOTest < MiniTest::Test
  def setup
    EV.rerun
  end

  def test_that_reading_works
    i, o = IO.pipe
    data = +''
    w = EV::IO.new(i, :r)
    w.start do
      i.read_nonblock(8192, data)
      w.stop unless data.empty?
    end
    EV::Timer.new(0, 0).start { o << 'hello' }
    suspend
    assert_equal('hello', data)
  end
end

class EVSignalTest < MiniTest::Test
  def setup
    EV.rerun
    EV.restart
  end

  def test_that_signal_watcher_receives_signal
    sig = Signal.list['USR1']
    count = 0
    w = EV::Signal.new(sig) { count += 1; w.stop }
    Thread.new { sync_sleep 0.001; Process.kill(:USR1, Process.pid) }
    suspend
    assert_equal(1, count)
  end

  def test_that_signal_watcher_receives_signal
    count = 0
    w = Polyphony.trap(:usr1, true) { count += 1; w.stop }
    assert_kind_of(EV::Signal, w)
    Thread.new { sync_sleep 0.001; Process.kill(:USR1, Process.pid) }
    suspend
    assert_equal(1, count)
  end
end

class EVAsyncTest < MiniTest::Test
  def setup
    EV.rerun
  end

  def test_that_async_watcher_receives_signal_across_threads
    count = 0
    a = EV::Async.new { count += 1; a.stop }
    Thread.new { sync_sleep 0.001; a.signal! }
    suspend
    assert_equal(1, count)
  end

  def test_that_async_watcher_coalesces_signals
    count = 0
    a = EV::Async.new do
      count += 1
      EV::Timer.new(0.01, 0).start { a.stop }
    end
    Thread.new do
      sync_sleep 0.001
      3.times { a.signal! }
    end
    suspend
    assert_equal(1, count)
  end
end