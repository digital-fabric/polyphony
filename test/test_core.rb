require 'minitest/autorun'
require 'modulation'

module CoreTests
  CancelScope = import('../lib/nuclear/core/cancel_scope')
  Core        = import('../lib/nuclear/core')
  Exceptions  = import('../lib/nuclear/core/exceptions')
  Supervisor  = import('../lib/nuclear/core/supervisor')
  Task        = import('../lib/nuclear/core/task')

  Core.dont_auto_run!

  class SpawnTest < MiniTest::Test
    def test_that_spawn_returns_a_task
      result = nil
      task = spawn { result = 42 }

      assert_kind_of(Task, task)
      assert_nil(result)
      EV.run
      assert_equal(42, result)
    end

    def test_that_spawn_accepts_task_argument
      result = nil
      task = Task.new { result = 42 }
      spawn task

      assert_nil(result)
      EV.run
      assert_equal(42, result)
    end

    def test_that_spawned_task_saves_result
      task = spawn { 42 }

      assert_kind_of(Task, task)
      assert_nil(task.result)
      EV.run
      assert_equal(42, task.result)
    end

    def test_that_spawned_task_can_be_stopped
      result = nil
      task = spawn { await sleep(1); 42 }
      EV.next_tick { task.stop! }
      EV.run
      assert_nil(task.result)
    end
  end

  class TaskTest < MiniTest::Test
    def test_that_task_can_be_awaited
      result = nil
      spawn do
        task = async { await sleep(0.001); 42 }
        result = await task
      end
      EV.run
      assert_equal(42, result)
    end

    def test_that_task_can_be_stopped
      result = nil
      task = spawn do
        await sleep(0.001)
        result = 42
      end
      EV.next_tick { task.stop! }
      EV.run
      assert_nil(result)
    end

    def test_that_task_can_be_cancelled
      result = nil
      task = spawn do
        await sleep(0.001)
        result = 42
      end
      EV.next_tick { task.cancel! }
      EV.run
      assert_nil(result)
      assert_kind_of(Exceptions::Cancelled, task.result)
      assert_nil(task.running?)
      assert(task.cancelled?)
    end

    def test_that_inner_task_can_be_cancelled
      result = nil
      task2 = nil
      task = spawn do
        task2 = async do
          await sleep(0.001)
          result = 42
        end
        await task2
        result && result += 1
      end
      EV.next_tick { task.cancel! }
      EV.run
      assert_nil(result)
      assert_nil(task.running?)
      assert_nil(task2.running?)
    end

    def test_that_inner_task_can_cancel_outer_task
      result = nil
      task2 = nil
      task = spawn do
        task2 = async do
          EV.next_tick { task.cancel! }
          await sleep(0.001)
          result = 42
        end
        await task2
        result && result += 1
      end
      EV.run
      assert_nil(result)
      assert_nil(task.running?)
      assert_nil(task2.running?)
      assert(task.cancelled?)
      assert(task2.cancelled?)
    end
  end

  class AwaitTest < Minitest::Test
    def test_that_await_passes_block_to_given_task
      task = spawn do
        await async do
          42
        end
      end
      EV.run
      assert_equal(42, task.result)
    end

    def test_that_await_works_with_an_already_spawned_task
      task = spawn do
        t = spawn { 42 }
        await t
      end
      EV.run
      assert_equal(42, task.result)
    end

    def test_that_await_blocks_execution
      task_started = nil
      timer_fired = nil
      result = nil
      task = proc do
        task_started = true
        fiber = Fiber.current
        timer = EV::Timer.new(0.01, 0)
        timer.start do
          timer_fired = true
          fiber.resume('hello')
        end
        suspend
      end
      assert_nil(task_started)
      
      spawn { result = await task }
      EV.run
      assert(task_started)
      assert(timer_fired)
      assert_equal('hello', result)
    end

    def test_that_await_accepts_block_and_passes_it_to_given_task
      result = nil
      spawn do
        result = await async { 42 }
      end
      # async returns a task that uses an EV signal to resolve, so we need to run
      # the event loop
      EV.run 
      assert_equal(42, result)
    end
  end

  class AsyncTest < MiniTest::Test
    def test_that_async_returns_a_task
      result = nil
      o = async { result = 1 }
      assert_kind_of(Task, o)

      # async should not by itself run the given block
      EV.run
      assert_nil(result)
    end

    async def add(x, y)
      x + y
    end
    
    def test_that_async_decorates_a_given_method
      assert(respond_to?(:sync_add))
      assert_equal(5, sync_add(2, 3))

      o = add(3, 4)
      assert_kind_of(Task, o)
      result = nil
      spawn do
        result = await o
      end
      assert_nil(result)
      EV.run
      assert_equal(7, result)

      result = nil
      spawn { result = await add(2, 3) }
      EV.run
      assert_equal(5, result)
    end
  end

  class CancelScopeTest < Minitest::Test
    def sleep_with_cancel(ctx, mode = nil)
      CancelScope.new(mode: mode).run do |c|
        ctx[:cancel_scope] = c
        ctx[:result] = await sleep(0.01)
      end
      ctx[:result] = await sleep(0.01)
    end

    def test_that_cancel_scope_cancels_task
      ctx = {}
      spawn do
        EV::Timer.new(0.005, 0).start { ctx[:cancel_scope]&.cancel! }
        sleep_with_cancel(ctx)
      rescue Exception => e
        ctx[:result] = e
      end
      assert_nil(ctx[:result])
      # async operation will only begin on next iteration of event loop
      assert_nil(ctx[:cancel_scope])
      
      EV.run
      assert_kind_of(CancelScope, ctx[:cancel_scope])
      assert_kind_of(Exceptions::Cancelled, ctx[:result])
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
          await sleep(1000)
        end
        result = 42
      rescue Exceptions::Cancelled
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
            await sleep(1000)
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
            await sleep(1000)
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
      async do
        await sleep(0.001 * idx)
        ctx[idx] = true
      end
    end

    def parallel_sleep(ctx)
      supervise do |s|
        (1..3).each { |idx| s << sleep_and_set(ctx, idx) }
      end
    end
    
    def test_that_supervisor_waits_for_all_nested_tasks_to_complete
      ctx = {}
      spawn do
        await parallel_sleep(ctx)
      end
      EV.run
      assert(ctx[1])
      assert(ctx[2])
      assert(ctx[3])
    end

    def test_that_supervisor_can_add_tasks_after_having_started
      result = []
      spawn do
        supervisor = Supervisor.new
        3.times do |i|
          spawn do
            await sleep(0.001)
            supervisor << async do
              await sleep(0.001)
              result << i
            end
          end
        end
        await supervisor
      end

      EV.run
      assert_equal([0, 1, 2], result)
    end
  end
end