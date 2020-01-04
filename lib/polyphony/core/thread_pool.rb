# frozen_string_literal: true

export :process, :setup, :size=, :busy?

@size = 10

def process(&block)
  setup unless @task_queue

  watcher = Gyro::Async.new
  @task_queue << [block, watcher]
  watcher.await
end

def size=(size)
  @size = size
end

def busy?
  !@queue.empty?
end

def setup
  @task_queue = ::Queue.new
  @threads = (1..@size).map { Thread.new { thread_loop } }
end

def thread_loop
  loop { run_queued_task }
end

def run_queued_task
  (block, watcher) = @task_queue.pop
  result = block.()
  watcher.signal!(result)
rescue Exception => e
  watcher.signal!(e)
end
