# frozen_string_literal: true

export :spawn

Core  = import('./core')
IO    = import('./io')

# Runs the given block in a separate thread, returning a promise fulfilled
# once the thread is done
def spawn(opts = {}, &block)
  Core::Async.promise(opts) do |p|
    i, o = ::IO.pipe
    ctx = {o: o}
    Thread.new { promised_thread(ctx, &block) }
    IO.new(i).on(:close) { i.close; p.complete(ctx[:value]) }
  end
end

# Runs the given block, 
def promised_thread(ctx, &block)
  ctx[:value] = block.()
rescue StandardError => e
  puts "error: #{e}"
  ctx[:value] = e
ensure
  ctx[:o].close
end