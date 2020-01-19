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
    fiber = Fiber.spin { result = 42 }

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
    defer { fiber.interrupt }
    suspend
    assert_nil fiber.result
  end
end

class CancelScopeTest < Minitest::Test
  def sleep_with_cancel(ctx, mode = nil)
    Polyphony::CancelScope.new(mode: mode).call do |c|
      ctx[:cancel_scope] = c
      ctx[:result] = sleep(0.01)
    end
  end

  def test_that_cancel_scope_cancels_fiber
    ctx = {}
    spin do
      after(0.005) { ctx[:cancel_scope].cancel! }
      sleep_with_cancel(ctx, :cancel)
    rescue Exception => e
      ctx[:result] = e
      nil
    end
    assert_nil ctx[:result]
    # async operation will only begin on next iteration of event loop
    assert_nil ctx[:cancel_scope]

    Thread.current.switch_fiber
    assert_kind_of Polyphony::CancelScope, ctx[:cancel_scope]
    assert_kind_of Polyphony::Cancel, ctx[:result]
  end

  def test_that_cancel_scope_cancels_async_op_with_stop
    ctx = {}
    spin do
      after(0) { ctx[:cancel_scope].cancel! }
      sleep_with_cancel(ctx, :stop)
    end

    Thread.current.switch_fiber
    assert ctx[:cancel_scope]
    assert_nil ctx[:result]
  end

  def test_that_cancel_after_raises_cancelled_exception
    result = nil
    spin do
      cancel_after(0.01) do
        sleep(1000)
      end
      result = 42
    rescue Polyphony::Cancel
      result = :cancelled
    end
    suspend
    assert_equal :cancelled, result
  end

  # def test_that_cancel_scopes_can_be_nested
  #   inner_result = nil
  #   outer_result = nil
  #   spin do
  #     Polyphony::CancelScope.new(timeout: 0.01) do
  #       Polyphony::CancelScope.new(timeout: 0.02) do
  #         sleep(1000)
  #       end
  #       inner_result = 42
  #     end
  #     outer_result = 42
  #   end
  #   suspend
  #   assert_nil inner_result
  #   assert_equal 42, outer_result

  #   Polyphony.reset!

  #   outer_result = nil
  #   spin do
  #     move_on_after(0.02) do
  #       move_on_after(0.01) do
  #         sleep(1000)
  #       end
  #       inner_result = 42
  #     end
  #     outer_result = 42
  #   end
  #   suspend
  #   assert_equal 42, inner_result
  #   assert_equal 42, outer_result
  # end
end

class SupervisorTest < MiniTest::Test
  def sleep_and_set(ctx, idx)
    proc do
      sleep(0.001 * idx)
      ctx[idx] = true
    end
  end

  def parallel_sleep(ctx)
    supervise do |s|
      (1..3).each { |idx| s.spin(&sleep_and_set(ctx, idx)) }
    end
  end

  def test_that_supervisor_waits_for_all_nested_fibers_to_complete
    ctx = {}
    spin do
      parallel_sleep(ctx)
    end
    suspend
    assert ctx[1]
    assert ctx[2]
    assert ctx[3]
  end

  def test_that_supervisor_can_add_fibers_after_having_started
    result = []
    spin do
      supervisor = Polyphony::Supervisor.new
      3.times do |i|
        spin do
          sleep(0.001)
          supervisor.spin do
            sleep(0.001)
            result << i
          end
        end
      end
      supervisor.await
    end.await

    assert_equal [0, 1, 2], result.sort
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
    5.times { |i| snooze }
  rescue Exception => e
    error = e
  ensure
    assert_kind_of RuntimeError, error
    assert_equal [2, 3], frames
  end

  def test_cross_fiber_backtrace_with_dead_calling_fiber
    error = nil
    spin do
      spin do
        spin do
          raise 'foo'
        end
      end
    end
    4.times { snooze }
  rescue Exception => e
    error = e
  ensure
    assert_kind_of RuntimeError, error
  end
end

class MoveOnAfterTest < MiniTest::Test
  def test_move_on_after
    t0 = Time.now
    v = move_on_after(0.01) do
      sleep 1
      :foo
    end
    t1 = Time.now

    assert t1 - t0 < 0.02
    assert_nil v
  end

  def test_move_on_after_with_value
    t0 = Time.now
    v = move_on_after(0.01, with_value: :bar) do
      sleep 1
      :foo
    end
    t1 = Time.now

    assert t1 - t0 < 0.02
    assert_equal :bar, v
  end

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

  def test_throttled_loop
    buffer = []
    counter = 0
    f = spin do
      throttled_loop(50) { buffer << (counter += 1) }
    end
    sleep 0.1
    f.stop
    assert counter >= 5 && counter <= 6
  end

  def test_throttled_loop_with_count
    buffer = []
    counter = 0
    f = spin do
      throttled_loop(50, count: 5) { buffer << (counter += 1) }
    end
    f.await
    assert_equal [1, 2, 3, 4, 5], buffer    
  end

  def test_every
    buffer = []
    f = spin do
      every(0.01) { buffer << 1 }
    end
    sleep 0.05
    f.stop
    assert (4..5).include?(buffer.size)
  end

  def test_sleep
    t0 = Time.now
    sleep 0.05
    elapsed = Time.now - t0
    assert (0.045..0.08).include? elapsed

    f = spin { sleep }
    snooze
    assert f.running?
    snooze
    assert f.running?
    f.stop
    assert !f.running?
  end
end