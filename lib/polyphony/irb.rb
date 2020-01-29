# frozen_string_literal: true

require 'polyphony'

# readline blocks the current thread, so we offload it to the blocking-ops
# thread pool. That way, the reactor loop can keep running while waiting for
# readline to return
module ::Readline
  alias_method :orig_readline, :readline

  def readline(*args)
    async = Gyro::Async.new
    Thread.new do
      result = orig_readline(*args)
      async.signal!(result)
    end
    async.await
  end
end
