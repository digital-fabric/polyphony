# frozen_string_literal: true

require 'polyphony'
require 'readline'

# readline blocks the current thread, so we offload it to the blocking-ops
# thread pool. That way, the reactor loop can keep running while waiting for
# readline to return
module ::Readline
  alias_method :orig_readline, :readline
  
  Worker = Polyphony::ThreadPool.new(1)
  
  def readline(*args)
    Worker.process { orig_readline(*args) }
  end
end
