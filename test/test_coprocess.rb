require 'minitest/autorun'
require 'bundler/setup'
require 'polyphony'

class CoprocessTest < MiniTest::Test
  def setup
    EV.rerun
  end

  def test_that_main_fiber_has_associated_coprocess
    assert_equal(Fiber.current, Polyphony::Coprocess.current.fiber)
    assert_equal(Polyphony::Coprocess.current, Fiber.current.coprocess)
  end

  def test_that_new_coprocess_starts_in_suspended_state
    result = nil
    coproc = Polyphony::Coprocess.new { result = 42 }
    assert_nil(result)
    coproc.await
    assert_equal(42, result)
  end

  def test_that_new_coprocess_runs_on_different_fiber
    coproc = Polyphony::Coprocess.new { Fiber.current }
    fiber = coproc.await
    assert(fiber != Fiber.current)
  end

  def test_that_await_blocks_until_coprocess_is_done
    result = nil
    coproc = Polyphony::Coprocess.new { sleep 0.001; result = 42 }
    coproc.await
    assert_equal(42, result)
  end

  def test_that_await_returns_the_coprocess_return_value
    coproc = Polyphony::Coprocess.new { [:foo, :bar] }
    assert_equal([:foo, :bar], coproc.await)
  end

  def test_that_await_raises_error_raised_by_coprocess
    result = nil
    coproc = Polyphony::Coprocess.new { raise 'foo' }
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
    coproc = Polyphony::Coprocess.new {
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
    assert_kind_of(Polyphony::Cancel, result[1])
  end

  def test_that_running_coprocess_can_be_interrupted
    # that is, stopped without exception
    result = []
    coproc = Polyphony::Coprocess.new {
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

  def test_that_coprocess_can_be_awaited
    result = nil
    spawn do
      coprocess = Polyphony::Coprocess.new { sleep(0.001); 42 }
      result = coprocess.await
    end
    suspend
    assert_equal(42, result)
  end

  def test_that_coprocess_can_be_stopped
    result = nil
    coprocess = spawn do
      sleep(0.001)
      result = 42
    end
    EV.next_tick { coprocess.interrupt }
    suspend
    assert_nil(result)
  end

  def test_that_coprocess_can_be_cancelled
    result = nil
    coprocess = spawn do
      sleep(0.001)
      result = 42
    rescue Polyphony::Cancel => e
      result = e
    end
    EV.next_tick { coprocess.cancel! }

    suspend

    assert_kind_of(Polyphony::Cancel, result)
    assert_kind_of(Polyphony::Cancel, coprocess.result)
    assert_nil(coprocess.running?)
  end

  def test_that_inner_coprocess_can_be_interrupted
    result = nil
    coprocess2 = nil
    coprocess = spawn do
      coprocess2 = spawn do
        sleep(0.001)
        result = 42
      end
      coprocess2.await
      result && result += 1
    end
    EV.next_tick { coprocess.interrupt }
    suspend
    assert_nil(result)
    assert_nil(coprocess.running?)
    assert_nil(coprocess2.running?)
  end

  def test_that_inner_coprocess_can_interrupt_outer_coprocess
    result, coprocess2 = nil
    
    coprocess = spawn do
      coprocess2 = spawn do
        EV.next_tick { coprocess.interrupt }
        sleep(0.001)
        result = 42
      end
      coprocess2.await
      result && result += 1
    end
    
    suspend
    
    assert_nil(result)
    assert_nil(coprocess.running?)
    assert_nil(coprocess2.running?)
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
