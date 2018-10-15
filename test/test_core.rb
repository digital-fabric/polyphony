require 'minitest/autorun'
require 'modulation'

module CoreTest
  Core        = import('../lib/nuclear/core')
  CancelScope = import('../lib/nuclear/core/cancel_scope')

  class AsyncAwaitTest < Minitest::Test
    def test_that_async_returns_a_proc
      result = nil
      o = async { result = 1 }
      assert_kind_of(Proc, o)
      # async should not by itself run the given block
      assert_nil(result)
    end

    async def add(x, y)
      x + y
    end
    
    def test_that_async_decorates_a_given_method
      assert(respond_to?(:sync_add))
      assert_equal(5, sync_add(2, 3))

      o = add(2, 3)
      assert_kind_of(Proc, o)
      result = nil
      async! { result = await add(2, 3) }
      EV.run
      assert_equal(5, result)
    end

    def test_that_async_bang_runs_the_given_block_in_a_separate_fiber
      main_fiber = Fiber.current
      task_fiber = nil
      result = nil
      done = nil
      async! { task_fiber = Fiber.current; result = 42; done = true }
      EV.run # run async task
      assert_equal(true, done)
      assert_equal(42, result)
      assert(task_fiber)
      assert(task_fiber != main_fiber)
    end

    def test_that_await_blocks_execution
      task_started = nil
      timer_fired = nil
      result = nil
      task = proc do
        task_started = true
        fiber = Fiber.current
        timer = EV::Timer.new(0.01, 0) do
          timer_fired = true
          fiber.resume('hello')
        end
        Fiber.yield_and_raise_error
      end
      assert_nil(task_started)
      
      async! { result = await task }
      EV.run
      assert(task_started)
      assert(timer_fired)
      assert_equal('hello', result)
    end

    def test_that_await_accepts_block_and_passes_it_to_given_task
      result = nil
      async! do
        result = await async { 42 }
      end
      # async returns a task that uses an EV signal to resolve, so we need to run
      # the event loop
      EV.run 
      assert_equal(42, result)
    end
  end

  class CancelScopeTest < Minitest::Test
    def sleep_with_cancel(ctx, mode = nil)
      CancelScope.new(mode: mode).run do |c|
        ctx[:cancel_scope] = c
        ctx[:result] = await Core.sleep(0.01)
      end
      # ctx[:result] = await Core.sleep(0.01)
    end

    def test_that_cancel_scope_cancels_async_op
      ctx = {}
      async! do
        begin
          EV::Timer.new(0.005, 0) { ctx[:cancel_scope]&.cancel! }
          sleep_with_cancel(ctx)
        rescue Exception => e
          ctx[:result] = e
        end
        nil
      end
      assert_nil(ctx[:result])
      # async operation will only begin on next iteration of event loop
      assert_nil(ctx[:cancel_scope])
      
      EV.run
      assert_kind_of(CancelScope, ctx[:cancel_scope])
      assert_kind_of(Cancelled, ctx[:result])
    end

    def test_that_cancel_scope_cancels_async_op_with_move_on
      ctx = {}
      async! do
        EV::Timer.new(0, 0) { ctx[:cancel_scope].cancel! }
        sleep_with_cancel(ctx, :move_on)
      end
      
      EV.run
      assert(ctx[:cancel_scope])
      assert_nil(ctx[:result])
    end

    def test_that_cancel_after_raises_cancelled_exception
      result = nil
      async! do
        begin
          cancel_after(0.01) do
            await Core.sleep(1000)
          end
          result = 42
        rescue Cancelled
          result = :cancelled
        end
      end
      EV.run
      assert_equal(:cancelled, result)
    end

    def test_that_cancel_scopes_can_be_nested
      inner_result = nil
      outer_result = nil
      async! do
        move_on_after(0.01) do
          move_on_after(0.02) do
            await Core.sleep(1000)
          end
          inner_result = 42
        end
        outer_result = 42
      end
      EV.run
      assert_nil(inner_result)
      assert_equal(42, outer_result)

      outer_result = nil
      async! do
        move_on_after(0.02) do
          move_on_after(0.01) do
            await Core.sleep(1000)
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

  class NexusTest < MiniTest::Test
    def sleep(ctx, idx)
      async do
        await Core.sleep(0.001 * idx)
        ctx[idx] = true
      end
    end

    def parallel_sleep(ctx)
      nexus do |n|
        (1..3).each { |idx| n << sleep(ctx, idx) }
      end
    end
    
    def test_that_nexus_waits_for_all_nested_tasks_to_complete
      ctx = {}
      async! do
        await parallel_sleep(ctx)
      end
      EV.run
      assert(ctx[1])
      assert(ctx[2])
      assert(ctx[3])
    end
  end
end