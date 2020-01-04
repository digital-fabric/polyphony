# frozen_string_literal: true

export :process

Exceptions = import('./exceptions')

def process(&block)
  watcher = Gyro::Async.new
  thread = Thread.new { run_in_thread(watcher, &block) }
  watcher.await
ensure
  thread.kill if thread.alive?
end

# Runs the given block, passing the result or exception to the given context
# @param ctx [Hash] context
# @return [void]
def run_in_thread(watcher)
  result = yield
  watcher.signal!(result)
rescue Exception => e
  watcher.signal!(e)
end
