require 'minitest/autorun'
require 'modulation'

class CoprocessTest < MiniTest::Test
  Core        = import('../lib/polyphony/core')
  Coprocess   = import('../lib/polyphony/core/coprocess')
  Exceptions  = import('../lib/polyphony/core/exceptions')

  def setup
    EV.rerun
  end

  def test_that_main_fiber_has_associated_coprocess
    assert_equal(Fiber.current, Coprocess.current.fiber)
    assert_equal(Coprocess.current, Fiber.current.coprocess)
  end

  def test_that_new_coprocess_starts_in_suspended_state
    result = nil
    coproc = Coprocess.new { result = 42 }
    assert_nil(result)
    coproc.await
    assert_equal(42, result)
  end

  def test_that_new_coprocess_runs_on_different_fiber
    coproc = Coprocess.new { Fiber.current }
    fiber = coproc.await
    assert(fiber != Fiber.current)
  end

  def test_that_await_blocks_until_coprocess_is_done
    result = nil
    coproc = Coprocess.new { sleep 0.001; result = 42 }
    coproc.await
    assert_equal(42, result)
  end

  def test_that_await_returns_the_coprocess_return_value
    coproc = Coprocess.new { [:foo, :bar] }
    assert_equal([:foo, :bar], coproc.await)
  end

  def test_that_await_raises_error_raised_by_coprocess
    result = nil
    coproc = Coprocess.new { raise 'foo' }
    begin
      result = coproc.await
    rescue => e
      result = { error: e }
    end
    assert_kind_of(Hash, result)
    assert_kind_of(RuntimeError, result[:error])
  end

  def test_that_running_coprocess_can_be_cancelled
    result = []
    coproc = Coprocess.new {
      result << 1
      sleep 0.002
      result << 2
    }
    EV::Timer.new(0.001, 0).start { coproc.cancel! }
    begin
      coproc.await
    rescue Exception => e
      result << e
    end
    assert_equal(2, result.size)
    assert_equal(1, result[0])
    assert_kind_of(Exceptions::Cancel, result[1])
  end

  def test_that_running_coprocess_can_be_interrupted
    # that is, stopped without exception
    result = []
    coproc = Coprocess.new {
      result << 1
      sleep 0.002
      result << 2
      3
    }
    EV::Timer.new(0.001, 0).start { coproc.stop(42) }

    await_result = coproc.await
    assert_equal(1, result.size)
    assert_equal(42, await_result)
  end
end

class MailboxTest < MiniTest::Test
  def setup
    EV.rerun
  end

  def test_that_coprocess_can_receive_messages
    msgs = []
    coproc = spawn {
      loop {
        msgs << receive
      }
    }

    EV.snooze # allow coproc to start
    
    3.times { |i| coproc << i; EV.snooze }

    assert_equal([0, 1, 2], msgs)
  ensure
    coproc.stop
  end

  def test_that_multiple_messages_sent_at_once_arrive
    msgs = []
    coproc = spawn {
      loop { 
        msgs << receive
      }
    }

    EV.snooze # allow coproc to start
    
    3.times { |i| coproc << i }

    EV.snooze

    assert_equal([0, 1, 2], msgs)
  ensure
    coproc.stop
  end
end
