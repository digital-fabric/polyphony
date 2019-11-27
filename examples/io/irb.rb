# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/auto_run'
require 'irb'

$counter = 0
timer = spin do
  throttled_loop(5) do
    $counter += 1
  end
end

# readline blocks the current thread, so we offload it to the blocking-ops
# thread pool. That way, the reactor loop can keep running while waiting for
# readline to return
module ::Readline
  alias_method :orig_readline, :readline
  def readline(*args)
    Polyphony::ThreadPool.process { orig_readline(*args) }
  end
end

at_exit { timer.stop }

puts 'try typing $counter to see the counter incremented in the background'
IRB.start
