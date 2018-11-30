require 'minitest/autorun'
require 'modulation'

module CoreTests
  CancelScope = import('../lib/rubato/core/cancel_scope')
  Core        = import('../lib/rubato/core')
  Coroutine   = import('../lib/rubato/core/coroutine')
  Exceptions  = import('../lib/rubato/core/exceptions')
  Supervisor  = import('../lib/rubato/core/supervisor')

  Core.dont_auto_run!

  class SpawnTest < MiniTest::Test
    def test_that_spawn_returns_a_coroutine
      result = nil
      coroutine = spawn { result = 42 }

      assert_kind_of(Coroutine, coroutine)
      assert_nil(result)
      EV.run
      assert_equal(42, result)
    end

    def test_that_spawn_accepts_coroutine_argument
      result = nil
      coroutine = Coroutine.new { result = 42 }
      spawn coroutine

      assert_nil(result)
      EV.run
      assert_equal(42, result)
    end

    def test_that_spawned_coroutine_saves_result
      coroutine = spawn { 42 }

      assert_kind_of(Coroutine, coroutine)
      assert_nil(coroutine.result)
      EV.run
      assert_equal(42, coroutine.result)
    end

    def test_that_spawned_coroutine_can_be_interrupted
      result = nil
      coroutine = spawn { sleep(1); 42 }
      EV.next_tick { coroutine.interrupt }
      EV.run
      assert_nil(coroutine.result)
    end
  end

  class CoroutineTest < MiniTest::Test
    def test_that_coroutine_can_be_awaited
      result = nil
      spawn do
        coroutine = Coroutine.new { sleep(0.001); 42 }
        result = coroutine.await
      end
      EV.run
      assert_equal(42, result)
    end

    def test_that_coroutine_can_be_stopped
      result = nil
      coroutine = spawn do
        sleep(0.001)
        result = 42
      end
      EV.next_tick { coroutine.interrupt }
      EV.run
      assert_nil(result)
    end

    def test_that_coroutine_can_be_cancelled
      result = nil
      coroutine = spawn do
        sleep(0.001)
        result = 42
      rescue Exceptions::Cancel => e
        result = e
      end
      EV.next_tick { coroutine.cancel! }

      EV.run

      assert_kind_of(Exceptions::Cancel, result)
      assert_kind_of(Exceptions::Cancel, coroutine.result)
      assert_nil(coroutine.running?)
    end

    def test_that_inner_coroutine_can_be_interrupted
      result = nil
      coroutine2 = nil
      coroutine = spawn do
        coroutine2 = spawn do
          sleep(0.001)
          result = 42
        end
        coroutine2.await
        result && result += 1
      end
      EV.next_tick { coroutine.interrupt }
      EV.run
      assert_nil(result)
      assert_nil(coroutine.running?)
      assert_nil(coroutine2.running?)
    end

    def test_that_inner_coroutine_can_interrupt_outer_coroutine
      result, coroutine2 = nil
      
      coroutine = spawn do
        coroutine2 = spawn do
          EV.next_tick { coroutine.interrupt }
          sleep(0.001)
          result = 42
        end
        coroutine2.await
        result && result += 1
      end
      
      EV.run
      
      assert_nil(result)
      assert_nil(coroutine.running?)
      assert_nil(coroutine2.running?)
    end
  end

  # class AwaitTest < Minitest::Test
  #   def test_that_await_passes_block_to_given_coroutine
  #     coroutine = spawn do
  #       await { 42 }
  #     end
  #     EV.run
  #     assert_equal(42, coroutine.result)
  #   end

  #   def test_that_await_works_with_an_already_spawned_coroutine
  #     coroutine = spawn do
  #       t = spawn { 42 }
  #       await t
  #     end
  #     EV.run
  #     assert_equal(42, coroutine.result)
  #   end

  #   def test_that_await_blocks_execution
  #     coroutine_started = nil
  #     timer_fired = nil
  #     result = nil
  #     coroutine = proc do
  #       coroutine_started = true
  #       fiber = Fiber.current
  #       timer = EV::Timer.new(0.01, 0)
  #       timer.start do
  #         timer_fired = true
  #         fiber.resume('hello')
  #       end
  #       suspend
  #     end
  #     assert_nil(coroutine_started)
      
  #     spawn { result = await coroutine }
  #     EV.run
  #     assert(coroutine_started)
  #     assert(timer_fired)
  #     assert_equal('hello', result)
  #   end

  #   def test_that_await_accepts_block_and_passes_it_to_given_coroutine
  #     result = nil
  #     spawn do
  #       result = await { 42 }
  #     end
  #     # async returns a coroutine that uses an EV signal to resolve, so we need to run
  #     # the event loop
  #     EV.run 
  #     assert_equal(42, result)
  #   end
  # end

  # class AsyncTest < MiniTest::Test
  #   def test_that_async_returns_a_coroutine
  #     result = nil
  #     o = async { result = 1 }
  #     assert_kind_of(Coroutine, o)

  #     # async should not by itself run the given block
  #     EV.run
  #     assert_nil(result)
  #   end

  #   def add(x, y)
  #     x + y
  #   end
    
  #   def test_that_async_decorates_a_given_method
  #     assert(respond_to?(:sync_add))
  #     assert_equal(5, sync_add(2, 3))

  #     o = add(3, 4)
  #     assert_kind_of(Coroutine, o)
  #     result = nil
  #     spawn do
  #       result = await o
  #     end
  #     assert_nil(result)
  #     EV.run
  #     assert_equal(7, result)

  #     result = nil
  #     spawn { result = await add(2, 3) }
  #     EV.run
  #     assert_equal(5, result)
  #   end
  # end

  class CancelScopeTest < Minitest::Test
    def sleep_with_cancel(ctx, mode = nil)
      CancelScope.new(mode: mode).call do |c|
        ctx[:cancel_scope] = c
        ctx[:result] = sleep(0.01)
      end
    end

    def test_that_cancel_scope_cancels_coroutine
      ctx = {}
      spawn do
        EV::Timer.new(0.005, 0).start { ctx[:cancel_scope]&.cancel! }
        sleep_with_cancel(ctx, :cancel)
      rescue Exception => e
        ctx[:result] = e
      end
      assert_nil(ctx[:result])
      # async operation will only begin on next iteration of event loop
      assert_nil(ctx[:cancel_scope])
      
      EV.run
      assert_kind_of(CancelScope, ctx[:cancel_scope])
      assert_kind_of(Exceptions::Cancel, ctx[:result])
    end

    # def test_that_cancel_scope_cancels_async_op_with_stop
    #   ctx = {}
    #   spawn do
    #     EV::Timer.new(0, 0).start { ctx[:cancel_scope].cancel! }
    #     sleep_with_cancel(ctx, :stop)
    #   end
      
    #   EV.run
    #   assert(ctx[:cancel_scope])
    #   assert_nil(ctx[:result])
    # end

    def test_that_cancel_after_raises_cancelled_exception
      result = nil
      spawn do
        cancel_after(0.01) do
          sleep(1000)
        end
        result = 42
      rescue Exceptions::Cancel
        result = :cancelled
      end
      EV.run
      assert_equal(:cancelled, result)
    end

    def test_that_cancel_scopes_can_be_nested
      inner_result = nil
      outer_result = nil
      spawn do
        move_on_after(0.01) do
          move_on_after(0.02) do
            sleep(1000)
          end
          inner_result = 42
        end
        outer_result = 42
      end
      EV.run
      assert_nil(inner_result)
      assert_equal(42, outer_result)

      outer_result = nil
      spawn do
        move_on_after(0.02) do
          move_on_after(0.01) do
            sleep(1000)
          end
          inner_result = 42
        end
        outer_result = 42
      end
      EV.run
      assert_equal(42, inner_result)
      assert_equal(42, outer_result)
    end
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
        (1..3).each { |idx| s.spawn sleep_and_set(ctx, idx) }
      end
    end
    
    def test_that_supervisor_waits_for_all_nested_coroutines_to_complete
      ctx = {}
      spawn do
        parallel_sleep(ctx)
      end
      EV.run
      assert(ctx[1])
      assert(ctx[2])
      assert(ctx[3])
    end

    def test_that_supervisor_can_add_coroutines_after_having_started
      result = []
      spawn do
        supervisor = Supervisor.new
        3.times do |i|
          spawn do
            sleep(0.001)
            supervisor.spawn do
              sleep(0.001)
              result << i
            end
          end
        end
        supervisor.await
      end

      EV.run
      assert_equal([0, 1, 2], result)
    end
  end
end