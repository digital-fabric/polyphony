require 'minitest/autorun'
require 'modulation'

Core = import('../lib/nuclear/core')

class LoopTest < Minitest::Test
  def teardown
    Core.reset!
  end

  def test_that_loop_exits_if_nothing_is_watched
    Core.run_reactor
    assert(true)
  end

  def test_that_loop_exits_once_no_timers_are_pending
    fired = false
    timeout = 0.05
    t = Time.now
    Core.timeout(timeout) { fired = true }
    Core.run_reactor
    elapsed = Time.now - t

    assert(fired)
    assert(elapsed >= timeout)
  end

  def test_that_loop_exists_once_nothing_is_monitored
    read_io, write_io = IO.pipe
    child = fork do
      write_io << 'hello!'
      write_io.close
    end

    msg = (+"")
    Core.watch(read_io, :r) do
      msg << read_io.read_nonblock(8192, exception: false)
      Core.unwatch(read_io)
    end
    Core.run_reactor
    Process.wait(child)
    assert_equal('hello!', msg)
  end
end
