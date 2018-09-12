# frozen_string_literal: true

export :spawn

Core  = import('./core')
IO    = import('./io')

# Cross-thread readiness cue
class Cue
  def initialize(&block)
    @i, @o = ::IO.pipe
    IO.new(@i).on(:close) do
      @i.close
      block.()
    end
  end

  def signal!
    @o.close
  end
end

# Runs the given block in a separate thread, returning a promise fulfilled
# once the thread is done. The signalling for the thread is done using an
# I/O pipe.
# @param opts [Hash] promise options
# @return [Core::Promise]
def spawn(opts = {}, &block)
  Core.promise(opts) do |p|
    ctx = { cue: Cue.new { p.complete(ctx[:value]) } }
    Thread.new { promised_thread(ctx, &block) }
  end
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
  ctx[:cue].signal!
end
