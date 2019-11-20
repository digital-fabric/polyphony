# frozen_string_literal: true

export :spawn

Exceptions = import('./exceptions')

# Runs the given block in a separate thread, returning a promise fulfilled
# once the thread is done. The signalling for the thread is done using an
# I/O pipe.
# @return [Proc]
def spawn(&block)
  async do
    ctx = {
      fiber:   Fiber.current,
      watcher: EV::Async.new { complete_thread_task(ctx) },
      thread:  Thread.new { run_in_thread(ctx, &block) }
    }
    ctx[:thread].report_on_exception = false
    ctx[:thread].abort_on_exception = false
    wait_for_thread(ctx)
  end
end

def wait_for_thread(ctx)
  suspend
rescue Exceptions::CoprocessInterrupt => e
  ctx[:fiber] = nil
  ctx[:thread]&.raise(e)
  raise e
ensure
  ctx[:watcher]&.stop
end

def complete_thread_task(ctx)
  ctx[:fiber]&.transfer ctx[:value]
end

# Runs the given block, passing the result or exception to the given context
# @param ctx [Hash] context
# @return [void]
def run_in_thread(ctx)
  ctx[:value] = yield
  ctx[:thread] = nil
  ctx[:watcher].signal!
rescue Exception => e
  ctx[:value] = e
  ctx[:watcher].signal! if ctx[:fiber]
  raise e
end
