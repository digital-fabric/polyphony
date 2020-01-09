# frozen_string_literal: true

require_relative 'helper'

class FiberTest < MiniTest::Test
  def test_that_new_spun_fiber_starts_in_suspended_state
    result = nil
    f = Fiber.spin { result = 42 }
    assert_nil result
    f.await
    assert_equal 42, result
  ensure
    f&.stop
  end

  def test_that_await_blocks_until_fiber_is_done
    result = nil
    f = Fiber.spin do
      snooze
      result = 42
    end
    f.await
    assert_equal 42, result
  ensure
    f&.stop
  end

  def test_that_await_returns_the_fibers_return_value
    f = Fiber.spin { %i[foo bar] }
    assert_equal %i[foo bar], f.await
  ensure
    f&.stop
  end

  def test_that_await_raises_error_raised_by_fiber
    result = nil
    f = Fiber.spin { raise 'foo' }
    begin
      result = f.await
    rescue Exception => e
      result = { error: e }
    end
    assert_kind_of Hash, result
    assert_kind_of RuntimeError, result[:error]
  ensure
    f&.stop
  end

  def test_that_running_fiber_can_be_cancelled
    result = []
    error = nil
    f = Fiber.spin do
      result << 1
      2.times { snooze }
      result << 2
    end
    defer { f.cancel! }
    assert_equal 0, result.size
    begin
      f.await
    rescue Polyphony::Cancel => e
      error = e
    end
    assert_equal 1, result.size
    assert_equal 1, result[0]
    assert_kind_of Polyphony::Cancel, error
  ensure
    f&.stop
  end

  def test_that_running_fiber_can_be_interrupted
    # that is, stopped without exception
    result = []
    f = Fiber.spin do
      result << 1
      2.times { snooze }
      result << 2
      3
    end
    defer { f.stop(42) }

    await_result = f.await
    assert_equal 1, result.size
    assert_equal 42, await_result
  ensure
    f&.stop
  end

  def test_that_fiber_can_be_awaited
    result = nil
    f2 = nil
    f1 = spin do
      f2 = Fiber.spin do
        snooze
        42
      end
      result = f2.await
    end
    suspend
    assert_equal 42, result
  ensure
    f1&.stop
    f2&.stop
  end

  def test_that_fiber_can_be_stopped
    result = nil
    f = spin do
      snooze
      result = 42
    end
    defer { f.interrupt }
    suspend
    assert_nil result
  ensure
    f&.stop
  end

  def test_that_fiber_can_be_cancelled
    result = nil
    f = spin do
      snooze
      result = 42
    rescue Polyphony::Cancel => e
      result = e
    end
    defer { f.cancel! }

    suspend

    assert_kind_of Polyphony::Cancel, result
    assert_kind_of Polyphony::Cancel, f.result
    assert_equal :dead, f.state
  ensure
    f&.stop
  end

  def test_that_inner_fiber_can_be_interrupted
    result = nil
    f2 = nil
    f1 = spin do
      f2 = spin do
        snooze
        result = 42
      end
      f2.await
      result && result += 1
    end
    defer { f2.interrupt }
    suspend
    assert_nil result
    assert_equal :dead, f1.state
    assert_equal :dead, f2.state
  ensure
    f1&.stop
    f2&.stop
  end

  def test_state
    counter = 0
    f = spin do
      3.times do
        snooze
        counter += 1
      end
    end

    assert_equal :scheduled, f.state
    assert_equal :running, Fiber.current.state
    snooze
    assert_equal :scheduled, f.state
    snooze while counter < 3
    assert_equal :dead, f.state
  ensure
    f&.stop
  end

  def test_fiber_exception_propagation
    # error is propagated to calling fiber
    raised_error = nil
    spin do
      spin do
        raise 'foo'
      end
      snooze # allow nested fiber to run before finishing
    end
    suspend
  rescue Exception => e
    raised_error = e
  ensure
    assert raised_error
    assert_equal 'foo', raised_error.message
  end

  def test_that_fiber_can_be_interrupted_before_first_scheduling
    buffer = []
    f = spin { buffer << 1 }
    f.stop

    snooze
    assert !f.running?
    assert_equal [], buffer
  end

  def test_exception_propagation_for_orphan_fiber
    raised_error = nil
    spin do
      spin do
        snooze
        raise 'bar'
      end
    end
    suspend
  rescue Exception => e
    raised_error = e
  ensure
    assert raised_error
    assert_equal 'bar', raised_error.message
  end

  def test_await_multiple_fibers
    f1 = spin { sleep 0.01; :foo }
    f2 = spin { sleep 0.01; :bar }
    f3 = spin { sleep 0.01; :baz }

    result = Fiber.await(f1, f2, f3)
    assert_equal %i{foo bar baz}, result
  end

  def test_join_multiple_fibers
    f1 = spin { sleep 0.01; :foo }
    f2 = spin { sleep 0.01; :bar }
    f3 = spin { sleep 0.01; :baz }

    result = Fiber.join(f1, f2, f3)
    assert_equal %i{foo bar baz}, result
  end

  def test_select_from_multiple_fibers
    buffer = []
    f1 = spin { sleep 0.01; buffer << :foo; :foo }
    f2 = spin { sleep 0.02; buffer << :bar; :bar }
    f3 = spin { sleep 0.03; buffer << :baz; :baz }

    result, selected = Fiber.select(f1, f2, f3)
    assert_equal :foo, result
    assert_equal f1, selected
    assert_equal [:foo], buffer
  end

  def test_caller
    location = /^#{__FILE__}:#{__LINE__ + 1}/
    f = spin do
      sleep 0.01
    end
    snooze

    caller = f.caller
    assert_match location, caller[0]
  end

  def test_location
    location = /^#{__FILE__}:#{__LINE__ + 1}/
    f = spin do
      sleep 0.01
    end
    snooze

    assert f.location =~ location
  end

  def test_when_done
    flag = nil
    values = []
    f = spin do
      snooze until flag
    end
    f.when_done { values << 42 }

    snooze
    assert values.empty?
    snooze
    flag = true
    assert values.empty?
    assert f.alive?

    snooze
    assert_equal [42], values
    assert !f.running?
  end

  def test_interrupt
    f = spin do
      sleep 1
      :foo
    end

    snooze
    assert f.alive?

    f.interrupt :bar
    assert !f.running?

    assert_equal :bar, f.result
  end

  def test_cancel
    error = nil
    f = spin do
      sleep 1
      :foo
    end

    snooze
    f.cancel!
  rescue Polyphony::Cancel => e
    # cancel error should bubble up
    error = e
  ensure
    assert error
    assert_equal :dead, f.state
  end
end

class MailboxTest < MiniTest::Test
  def test_that_fiber_can_receive_messages
    msgs = []
    f = spin { loop { msgs << receive } }

    snooze # allow fiber to start

    3.times do |i|
      f << i
      snooze
    end

    assert_equal [0, 1, 2], msgs
  ensure
    f&.stop
  end

  def test_that_multiple_messages_sent_at_once_arrive_in_order
    msgs = []
    f = spin { loop { msgs << receive } }

    snooze # allow coproc to start

    3.times { |i| f << i }

    snooze

    assert_equal [0, 1, 2], msgs
  ensure
    f&.stop
  end

  def test_that_sent_message_are_queued_before_calling_receive
    buffer = []
    receiver = spin { suspend; 3.times { buffer << receive } }
    sender = spin { 3.times { |i| receiver << (i * 10) } }

    sender.await
    receiver.schedule
    receiver.await

    assert_equal [0, 10, 20], buffer
  end

  def test_list_and_count
    assert_equal 1, Fiber.count
    assert_equal [Fiber.current], Fiber.list

    f = spin { sleep 1 }
    snooze
    assert_equal 2, Fiber.count
    assert_equal f, Fiber.list.last

    f.stop
    snooze
    assert_equal 1, Fiber.count
  end
end
