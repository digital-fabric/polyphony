# frozen_string_literal: true

export :spawn, :Cue

Core  = import('./core')
IO    = import('./io')

# Runs the given block in a separate thread, returning a promise fulfilled
# once the thread is done. The signalling for the thread is done using an
# I/O pipe.
# @param opts [Hash] promise options
# @return [Core::Promise]
def spawn(opts = {}, &block)
  Core.promise(opts) do |p|
    ctx = { watcher: EV::Async.new { complete_thread_promise(p, ctx) } }
    Thread.new { promised_thread(ctx, &block) }
  end
end

def complete_thread_promise(p, ctx)
  p.complete(ctx[:value])
  ctx[:watcher].stop
end

# Runs the given block, passing the result or exception to the given context
# @param ctx [Hash] context
# @return [void]
def promised_thread(ctx)
  ctx[:value] = yield
rescue StandardError => e
  puts "error: #{e}"
  ctx[:value] = e
ensure
  ctx[:watcher].signal!
end
