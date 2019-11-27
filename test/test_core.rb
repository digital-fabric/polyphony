# frozen_string_literal: true

require_relative 'helper'

class SpinTest < MiniTest::Test
  def test_that_spin_returns_a_coprocess
    result = nil
    coprocess = spin { result = 42 }

    assert_kind_of(Polyphony::Coprocess, coprocess)
    assert_nil(result)
    suspend
    assert_equal(42, result)
  end

  def test_that_spin_accepts_coprocess_argument
    result = nil
    coprocess = Polyphony::Coprocess.new { result = 42 }
    coprocess.run

    assert_nil(result)
    suspend
    assert_equal(42, result)
  end

  def test_that_spined_coprocess_saves_result
    coprocess = spin { 42 }

    assert_kind_of(Polyphony::Coprocess, coprocess)
    assert_nil(coprocess.result)
    suspend
    assert_equal(42, coprocess.result)
  end

  def test_that_spined_coprocess_can_be_interrupted
    coprocess = spin do
      sleep(1)
      42
    end
    defer { coprocess.interrupt }
    suspend
    assert_nil(coprocess.result)
  end
end

class CancelScopeTest < Minitest::Test
  def sleep_with_cancel(ctx, mode = nil)
    Polyphony::CancelScope.new(mode: mode).call do |c|
      ctx[:cancel_scope] = c
      ctx[:result] = sleep(0.01)
    end
  end

  def test_that_cancel_scope_cancels_coprocess
    ctx = {}
    spin do
      Gyro::Timer.new(0.005, 0).start { ctx[:cancel_scope]&.cancel! }
      sleep_with_cancel(ctx, :cancel)
    rescue Exception => e
      ctx[:result] = e
    end
    assert_nil(ctx[:result])
    # async operation will only begin on next iteration of event loop
    assert_nil(ctx[:cancel_scope])

    suspend
    assert_kind_of(Polyphony::CancelScope, ctx[:cancel_scope])
    assert_kind_of(Polyphony::Cancel, ctx[:result])
  end

  # def test_that_cancel_scope_cancels_async_op_with_stop
  #   ctx = {}
  #   spin do
  #     Gyro::Timer.new(0, 0).start { ctx[:cancel_scope].cancel! }
  #     sleep_with_cancel(ctx, :stop)
  #   end

  #   suspend
  #   assert(ctx[:cancel_scope])
  #   assert_nil(ctx[:result])
  # end

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
    assert_equal(:cancelled, result)
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
  #   assert_nil(inner_result)
  #   assert_equal(42, outer_result)

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
  #   assert_equal(42, inner_result)
  #   assert_equal(42, outer_result)
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
      (1..3).each { |idx| s.spin sleep_and_set(ctx, idx) }
    end
  end

  def test_that_supervisor_waits_for_all_nested_coprocesses_to_complete
    ctx = {}
    spin do
      parallel_sleep(ctx)
    end
    suspend
    assert(ctx[1])
    assert(ctx[2])
    assert(ctx[3])
  end

  def test_that_supervisor_can_add_coprocesses_after_having_started
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

    assert_equal([0, 1, 2], result)
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
    4.times { snooze }
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
