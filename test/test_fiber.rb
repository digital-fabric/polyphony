# frozen_string_literal: true

require_relative 'helper'

class FiberTest < MiniTest::Test
  def test_spin_initial_state
    result = nil
    f = Fiber.spin { result = 42 }
    assert_nil result
    f.await
    assert_equal 42, result
  ensure
    f&.stop
  end

  def test_await
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

  def test_tag
    assert_equal :main, Fiber.current.tag
    Fiber.current.tag = :foo
    assert_equal :foo, Fiber.current.tag

    f = Fiber.spin(:bar) { }
    assert_equal :bar, f.tag
  end

  def test_await_return_value
    f = Fiber.spin { %i[foo bar] }
    assert_equal %i[foo bar], f.await
  ensure
    f&.stop
  end

  def test_await_with_error
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

  def test_raise
    result = []
    error = nil
    f = Fiber.spin do
      result << 1
      2.times { snooze }
      result << 2
    end
    defer { f.raise }
    assert_equal 0, result.size
    begin
      f.await
    rescue Exception => e
      error = e
    end
    assert_equal 1, result.size
    assert_equal 1, result[0]
    assert_kind_of RuntimeError, error
  ensure
    f&.stop
  end

  class MyError < RuntimeError
  end

  def test_raise_with_error_class
    result = []
    error = nil
    f = Fiber.spin do
      result << 1
      2.times { snooze }
      result << 2
    end
    defer { f.raise MyError }
    assert_equal 0, result.size
    begin
      f.await
    rescue Exception => e
      error = e
    end
    assert_equal 1, result.size
    assert_equal 1, result[0]
    assert_kind_of MyError, error
  ensure
    f&.stop
  end

  def test_raise_with_error_class_and_message
    result = []
    error = nil
    f = Fiber.spin do
      result << 1
      2.times { snooze }
      result << 2
    end
    defer { f.raise(MyError, 'foo') }
    assert_equal 0, result.size
    begin
      f.await
    rescue Exception => e
      error = e
    end
    assert_equal 1, result.size
    assert_equal 1, result[0]
    assert_kind_of MyError, error
    assert_equal 'foo', error.message
  ensure
    f&.stop
  end

  def test_raise_with_message
    result = []
    error = nil
    f = Fiber.spin do
      result << 1
      2.times { snooze }
      result << 2
    end
    defer { f.raise 'foo' }
    assert_equal 0, result.size
    begin
      f.await
    rescue Exception => e
      error = e
    end
    assert_equal 1, result.size
    assert_equal 1, result[0]
    assert_kind_of RuntimeError, error
    assert_equal 'foo', error.message
  ensure
    f&.stop
  end

  def test_raise_with_exception
    result = []
    error = nil
    f = Fiber.spin do
      result << 1
      2.times { snooze }
      result << 2
    end
    defer { f.raise MyError.new('bar') }
    assert_equal 0, result.size
    begin
      f.await
    rescue Exception => e
      error = e
    end
    assert_equal 1, result.size
    assert_equal 1, result[0]
    assert_kind_of MyError, error
    assert_equal 'bar', error.message
  ensure
    f&.stop
  end

  def test_cancel
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

  def test_interrupt
    # that is, stopped without exception
    result = []
    f = Fiber.spin do
      result << 1
      2.times { snooze }
      result << 2
      3
    end
    defer { f.interrupt(42) }

    await_result = f.await
    assert_equal 1, result.size
    assert_equal 42, await_result
  ensure
    f&.stop
  end

  def test_stop
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

  def test_interrupt_before_start
    result = []
    f = Fiber.spin do
      result << 1
    end
    f.interrupt(42)
    snooze

    assert_equal :dead, f.state
    assert_equal [], result
    assert_equal 42, f.result
  end

  def test_interrupt_nested_fiber
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
      suspend
    end

    assert_equal :runnable, f.state
    assert_equal :running, Fiber.current.state
    snooze
    assert_equal :runnable, f.state
    snooze while counter < 3
    assert_equal :waiting, f.state
    f.stop
    assert_equal :dead, f.state
  ensure
    f&.stop
  end

  def test_exception_bubbling
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

  def test_exception_bubling_for_orphan_fiber
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
    f2 = spin { sleep 0.03; buffer << :bar; :bar }
    f3 = spin { sleep 0.05; buffer << :baz; :baz }

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

  def test_inspect
    expected = format('#<Fiber:%s (root) (running)>', Fiber.current.object_id)
    assert_equal expected, Fiber.current.inspect

    spin_line_no = __LINE__ + 1
    f = spin { :foo }

    expected = format(
      '#<Fiber:%s %s:%d:in `test_inspect\' (runnable)>',
      f.object_id,
      __FILE__,
      spin_line_no
    )
    assert_equal expected, f.inspect

    f.await
    expected = format(
      '#<Fiber:%s %s:%d:in `test_inspect\' (dead)>',
      f.object_id,
      __FILE__,
      spin_line_no
    )
    assert_equal expected, f.inspect
  end

  def test_system_exit_in_fiber
    parent_error = nil
    main_fiber_error = nil
    f2 = nil
    f1 = spin do
      f2 = spin { raise SystemExit }
      suspend
    rescue Exception => parent_error
    end

    begin
      suspend
    rescue Exception => main_fiber_error
    end

    assert_nil parent_error
    assert_kind_of SystemExit, main_fiber_error
  end

  def test_interrupt_in_fiber
    parent_error = nil
    main_fiber_error = nil
    f2 = nil
    f1 = spin do
      f2 = spin { raise Interrupt }
      suspend
    rescue Exception => parent_error
    end

    begin
      suspend
    rescue Exception => main_fiber_error
    end

    assert_nil parent_error
    assert_kind_of Interrupt, main_fiber_error
  end
end
