# frozen_string_literal: true

require_relative 'helper'

class SpinTest < MiniTest::Test
  def test_that_spin_returns_a_fiber
    result = nil
    fiber = spin { result = 42 }

    assert_kind_of Fiber, fiber
    assert_nil result
    suspend
    assert_equal 42, result
  end

  def test_that_spin_accepts_fiber_argument
    result = nil
    fiber = Fiber.current.spin { result = 42 }

    assert_nil result
    suspend
    assert_equal 42, result
  end

  def test_that_spined_fiber_saves_result
    fiber = spin { 42 }

    assert_kind_of Fiber, fiber
    assert_nil fiber.result
    suspend
    assert_equal 42, fiber.result
  end

  def test_that_spined_fiber_can_be_interrupted
    fiber = spin do
      sleep(1)
      42
    end
    spin { fiber.interrupt }
    suspend
    assert_nil fiber.result
  end

  def test_spin_without_tag
    f = spin { }
    assert_kind_of Fiber, f
    assert_nil f.tag
  end

  def test_spin_with_tag
    f = spin(:foo) { }
    assert_kind_of Fiber, f
    assert_equal :foo, f.tag
  end
end

class ExceptionTest < MiniTest::Test
  def test_cross_fiber_backtrace
    error = nil
    frames = []
    spin do
      spin do
        spin do
          raise 'foo'
        end
        suspend
      rescue Exception => e
        frames << 2
        raise e
      end
      suspend
    rescue Exception => e
      frames << 3
      raise e
    end
    begin
      5.times { snooze }
    rescue Exception => e
      error = e
    ensure
      assert_kind_of RuntimeError, error
      assert_equal [2, 3], frames
    end
  end

  def test_cross_fiber_backtrace_with_dead_calling_fiber
    error = nil
    begin
      spin do
        spin do
          spin do
            raise 'foo'
          end.await
        end.await
      end.await
    rescue Exception => e
      error = e
    ensure
      assert_kind_of RuntimeError, error
    end
  end
end

class MoveOnAfterTest < MiniTest::Test
  def test_move_on_after
    t0 = monotonic_clock
    v = move_on_after(0.01) do
      sleep 1
      :foo
    end
    t1 = monotonic_clock

    assert t1 - t0 < 0.1
    assert_nil v
  end

  def test_move_on_after_with_value
    t0 = monotonic_clock
    v = move_on_after(0.01, with_value: :bar) do
      sleep 1
      :foo
    end
    t1 = monotonic_clock

    assert t1 - t0 < 0.1
    assert_equal :bar, v
  end

  def test_move_on_after_with_reset
    t0 = monotonic_clock
    v = move_on_after(0.01, with_value: :moved_on) do |timeout|
      sleep 0.007
      timeout.reset
      sleep 0.007
      nil
    end
    t1 = monotonic_clock

    assert_nil v
    assert_in_range 0.014..0.025, t1 - t0 if IS_LINUX
  end

  def test_nested_move_on_after
    skip unless IS_LINUX

    t0 = monotonic_clock
    o = move_on_after(0.01, with_value: 1) do
      move_on_after(0.03, with_value: 2) do
        sleep 1
      end
    end
    t1 = monotonic_clock
    assert_equal 1, o
    assert_in_range 0.008..0.027, t1 - t0 if IS_LINUX

    t0 = monotonic_clock
    o = move_on_after(0.05, with_value: 1) do
      move_on_after(0.01, with_value: 2) do
        sleep 1
      end
    end
    t1 = monotonic_clock
    assert_equal 2, o
    assert_in_range 0.008..0.025, t1 - t0 if IS_LINUX
  end
end

class CancelAfterTest < MiniTest::Test
  def test_cancel_after
    t0 = monotonic_clock

    assert_raises Polyphony::Cancel do
      cancel_after(0.01) do
        sleep 1
        :foo
      end
    end
    t1 = monotonic_clock
    assert t1 - t0 < 0.1
  end

  def test_cancel_after_with_reset
    t0 = monotonic_clock
    cancel_after(0.1) do |f|
      assert_kind_of Fiber, f
      assert_equal Fiber.current, f.parent
      sleep 0.05
      f.reset
      sleep 0.05
      f.reset
      sleep 0.05
    end
    t1 = monotonic_clock
    assert_in_range 0.14..0.24, t1 - t0 if IS_LINUX
  end

  class CustomException < Exception
  end

  def test_cancel_after_with_custom_exception
    assert_raises CustomException do
      cancel_after(0.01, with_exception: CustomException) do
        sleep 1
        :foo
      end
    end

    begin
      err = nil
      cancel_after(0.01, with_exception: [CustomException, 'custom message']) do
        sleep 1
        :foo
      end
    rescue Exception => err
    ensure
      assert_kind_of CustomException, err
      assert_equal 'custom message', err.message
    end


    begin
      e = nil
      cancel_after(0.01, with_exception: 'foo') do
        sleep 1
        :foo
      end
    rescue => e
    ensure
      assert_kind_of RuntimeError, e
      assert_equal 'foo', e.message
    end
  end

  def test_lots_of_cancel_after
    cancels = 100

    cancel_count = 0
    cancels.times do
      begin
        cancel_after(0.001) { sleep 1 }
      rescue Polyphony::Cancel
        cancel_count += 1
      end
    end
    assert_equal cancels, cancel_count
  end

  def test_cancel_after_with_lots_of_resets
    resets = 100

    t0 = monotonic_clock
    cancel_after(0.1) do |f|
      resets.times do
        sleep 0.0001
        f.reset
      end
    end
    t1 = monotonic_clock
    assert_in_range 0.01..0.2, t1 - t0 if IS_LINUX
  end
end


class SpinLoopTest < MiniTest::Test
  def test_spin_loop
    buffer = []
    counter = 0
    f = spin_loop do
      buffer << (counter += 1)
      snooze
    end

    assert_kind_of Fiber, f
    assert_equal [], buffer
    snooze
    assert_equal [1], buffer
    snooze
    assert_equal [1, 2], buffer
    snooze
    assert_equal [1, 2, 3], buffer
    f.stop
    snooze
    assert !f.running?
    assert_equal [1, 2, 3], buffer
  end

  def test_spin_loop_location
    location = /^#{__FILE__}:#{__LINE__ + 1}/
    f = spin_loop { snooze }

    assert_match location, f.location
  end

  def test_spin_loop_tag
    f = spin_loop(:my_loop) { snooze }

    assert_equal :my_loop, f.tag
  end

  def test_spin_loop_with_rate
    buffer = []
    counter = 0
    t0 = monotonic_clock
    f = spin_loop(rate: 100) { buffer << (counter += 1) }
    sleep 0.02
    f.stop
    assert_in_range 1..3, counter if IS_LINUX
  end

  def test_spin_loop_with_interval
    buffer = []
    counter = 0
    t0 = monotonic_clock
    f = spin_loop(interval: 0.01) { buffer << (counter += 1) }
    sleep 0.02
    f.stop
    assert_in_range 1..3, counter if IS_LINUX
  end

  def test_spin_loop_break
    i = 0
    f = spin_loop do
      i += 1
      snooze
      break if i >= 5
    end
    f.await
    assert_equal 5, i

    i = 0
    f = spin_loop do
      i += 1
      snooze
      raise StopIteration if i >= 5
    end
    f.await
    assert_equal 5, i
  end

  def test_throttled_spin_loop_break
    i = 0
    f = spin_loop(rate: 100) do
      i += 1
      break if i >= 5
    end
    f.await
    assert_equal 5, i
  end
end

class SpinScopeTest < MiniTest::Test
  def test_spin_scope
    queue = Queue.new
    buffer = {}
    spin do
      queue << 1
      snooze
      queue << 2
    end
    f = nil
    result = spin_scope do
      f = Fiber.current
      spin { buffer[:a] = queue.shift }
      spin { buffer[:b] = queue.shift }
      :foo
    end
    assert_equal :foo, result
    assert_kind_of Fiber, f
    assert_equal :dead, f.state
    assert_equal ({a: 1, b: 2}), buffer
  end

  def test_spin_scope_with_exception
    queue = Queue.new
    buffer = []
    spin do
      spin_scope do
        spin { buffer << queue.shift }
        spin { raise 'foobar' }
      end
    rescue => e
      buffer << e.message
    end
    10.times { snooze }
    assert_equal 0, Fiber.current.children.size
    assert_equal ['foobar'], buffer
  end
end

class ThrottledLoopTest < MiniTest::Test
  def test_throttled_loop
    buffer = []
    counter = 0
    t0 = monotonic_clock
    f = spin do
      throttled_loop(10) { buffer << (counter += 1) }
    end
    sleep 0.3
    assert_in_range 2..4, counter if IS_LINUX
  end

  def test_throttled_loop_with_count
    buffer = []
    counter = 0
    t0 = monotonic_clock
    f = spin do
      throttled_loop(50, count: 5) { buffer << (counter += 1) }
    end
    f.await
    t1 = monotonic_clock
    assert_in_range 0.075..0.15, t1 - t0 if IS_LINUX
    assert_equal [1, 2, 3, 4, 5], buffer
  end

  def test_throttled_loop_inside_move_on_after
    count = 0
    move_on_after(0.1) do
      throttled_loop(50) { count += 1 }
    end
    assert_in_range 3..7, count
  end
end

class GlobalAPIEtcTest < MiniTest::Test
  def test_after
    buffer = []
    f = after(0.001) { buffer << 2 }
    snooze
    assert_equal [], buffer
    sleep 0.0015
    assert_equal [2], buffer
  end

  def test_every
    buffer = []
    t0 = monotonic_clock
    f = spin do
      every(0.01) { buffer << 1 }
    end
    sleep 0.05
    f.stop
    assert_in_range 4..6, buffer.size if IS_LINUX
  end

  def test_every_with_slow_op
    buffer = []
    t0 = monotonic_clock
    f = spin do
      every(0.01) { sleep 0.05; buffer << 1 }
    end
    sleep 0.15
    f.stop
    assert_in_range 2..3, buffer.size if IS_LINUX
  end

  def test_sleep
    t0 = monotonic_clock
    sleep 0.1
    elapsed = monotonic_clock - t0
    assert_in_range 0.05..0.15, elapsed if IS_LINUX

    f = spin { sleep }
    snooze
    assert f.running?
    snooze
    assert f.running?
    f.stop
    snooze
    assert !f.running?
  end

  def test_snooze
    values = []
    3.times.map do |i|
      spin do
        3.times do
          snooze
          values << i
        end
        suspend
      end
    end
    suspend

    assert_equal [0, 1, 2, 0, 1, 2, 0, 1, 2], values
  end

  def test_defer
    values = []
    spin { values << 1 }
    spin { values << 2 }
    spin { values << 3 }
    suspend

    assert_equal [1, 2, 3], values
  end

  def test_suspend
    values = []
    spin do
      values << :foo
      suspend
    end
    suspend

    assert_equal [:foo], values
  end

  def test_schedule_and_suspend
    values = []
    3.times.map do |i|
      spin do
        values << i
        suspend
      end
    end
    suspend

    assert_equal [0, 1, 2], values
  end
end
