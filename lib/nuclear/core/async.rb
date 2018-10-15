# frozen_string_literal: true

export :async_decorate, :async_task

FiberPool = import('./fiber_pool')

# Converts a regular method into an async method, i.e. a method that returns a
# proc that eventually executes the original code.
# @param receiver [Object] object receiving the method call
# @param sym [Symbol] method name
# @return [void]
def async_decorate(receiver, sym)
  sync_sym = :"sync_#{sym}"
  receiver.alias_method(sync_sym, sym)
  receiver.define_method(sym) do |*args, &block|
    MODULE.async_task { send(sync_sym, *args, &block) }
  end
end

# Calls a proc with a block if both are given. Otherwise, call the first
# non-nil proc. This allows syntax such as:
#
#     # in fact, the call to #nexus returns a proc which takes a block
#     await nexus { ... }
#
# @param proc [Proc] proc A
# @param block [Proc] proc B
# @return [any] return value of proc invocation
def call_proc_with_optional_block(proc, block)
  if proc && block
    proc.call(&block)
  else
    (proc || block).call
  end
end

# Return a proc wrapping the given block for execution as an async task. The
# returned proc will execute the given block inside a separate fiber.
# @return [Proc]
def async_task(&block)
  proc do |opts = {}, &block2|
    calling_fiber = Fiber.current
    if calling_fiber.root?
      FiberPool.spawn { call_proc_with_optional_block(block, block2) }
    else
      start_async_task(calling_fiber, block, block2, opts)
    end
  end.tap { |p| p.async = true }
end

# Starts the given task (represented by two block arguments) on a separate
# fiber, optionally waiting for the task to complete.
# @param calling_fiber [Fiber] calling fiber
# @param block [Proc] proc A
# @param block2 [Proc] proc B
# @param opts [Hash] async execution options
# @return [any] result of async task
def start_async_task(calling_fiber, block, block2, opts)
  ctx = { calling_fiber: calling_fiber }

  next_tick do
    FiberPool.spawn { |fiber| run_task(fiber, ctx, opts, block, block2) }
  end
  wait_for_task(calling_fiber, ctx, opts)
rescue Cancelled, MoveOn => e
  ctx[:calling_fiber] = nil
  ctx[:task_fiber]&.resume(e)
  raise e
end

# Runs an async task with optional life cycle hooks
# @param fiber [Fiber] fiber in which the task is running
# @param ctx [Hash] execution context
# @param opts [Hash] async execution options
# @param block [Proc] proc A
# @param block2 [Proc] proc A
# @return [void]
def run_task(fiber, ctx, opts, block, block2)
  ctx[:task_fiber] = fiber
  opts[:on_start]&.call(fiber)
  ctx[:result] = call_proc_with_optional_block(block, block2)
  finalize_task(ctx, opts)
rescue Exception => error
  ctx[:result] = error
  finalize_task(ctx, opts)
end

# Finalizes task by resuming controlling fiber or calling on_done hook.
# @param ctx [Hash] execution context
# @param opts [Hash] async execution options
# @return [void]
def finalize_task(ctx, opts)
  fiber = ctx[:task_fiber]
  ctx[:task_fiber] = nil
  ctx[:done] = true
  if opts[:on_done]
    opts[:on_done].call(fiber, ctx[:result])
  else
    ctx[:calling_fiber]&.resume(ctx[:result])
  end
end

# Waits tentatively for a task by optionally yielding
# @param calling_fiber [Fiber] calling fiber
# @param ctx [Hash] execution context
# @param opts [Hash] async execution options
# @return [any] result of async task
def wait_for_task(calling_fiber, ctx, opts)
  return if opts[:no_block] || !calling_fiber

  if ctx[:done]
    ctx[:result]
  else
    ctx[:calling_fiber] = calling_fiber
    Fiber.yield_and_raise_error
  end
end
