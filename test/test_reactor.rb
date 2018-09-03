require 'minitest/autorun'
require 'modulation'

Reactor = import('../lib/nuclear/reactor')

class LoopTest < Minitest::Test
  def teardown
    Reactor.reset!
  end

  def test_that_loop_exits_if_nothing_is_watched
    Reactor.loop
    assert(true)
  end

  def test_that_loop_exits_once_no_timers_are_pending
    fired = false
    timeout = 0.05
    Reactor.timeout(timeout) { fired = true }
    t = Time.now
    Reactor.loop
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
    Reactor.watch(read_io, :r) do
      msg << read_io.read_nonblock(8192, exception: false)
      Reactor.unwatch(read_io)
    end
    Reactor.loop
    Process.wait(child)
    assert_equal('hello!', msg)
  end
end
