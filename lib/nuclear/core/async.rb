# frozen_string_literal: true

export  :async_decorate, :async_task

FiberPool = import('./fiber_pool')

def async_decorate(receiver, sym)
  sync_sym = :"sync_#{sym}"
  receiver.alias_method(sync_sym, sym)
  receiver.define_method(sym) do |*args, &block|
    MODULE.async_task { send(sync_sym, *args, &block) }
  end
end

def call_proc_with_optional_block(proc, block)
  if proc && block
    proc.call(&block)
  else
    (proc || block).call
  end
end

def async_task(&block)
  proc do |opts = {}, &block2|
    calling_fiber = Fiber.current
    if calling_fiber.root?
      FiberPool.spawn { |f| call_proc_with_optional_block(block, block2) }
    else
      start_async_task(calling_fiber, block, block2, opts)
    end
  end.tap { |p| p.async = true }
end

def start_async_task(calling_fiber, block, block2, opts)
  ctx = {calling_fiber: calling_fiber}

  next_tick do
    FiberPool.spawn { |fiber| run_task(fiber, ctx, opts, block, block2) }
  end
  wait_for_task(calling_fiber, ctx, opts)
rescue Cancelled, MoveOn => e
  ctx[:calling_fiber] = nil
  ctx[:task_fiber]&.resume(e)
  raise e
end

def run_task(fiber, ctx, opts, block, block2)
  ctx[:task_fiber] = fiber
  begin
    opts[:on_start]&.call(fiber)
    ctx[:result] = call_proc_with_optional_block(block, block2)
    finalize_task(ctx, opts)
  rescue Exception => error
    ctx[:result] = error
    finalize_task(ctx, opts)
  end
end

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

def wait_for_task(calling_fiber, ctx, opts)
  return if opts[:no_block] || !calling_fiber

  if ctx[:done]
    ctx[:result]
  else
    ctx[:calling_fiber] = calling_fiber
    Fiber.yield_and_raise_error
  end
end