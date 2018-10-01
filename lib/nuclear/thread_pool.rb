# frozen_string_literal: true

export :process, :setup, :size=, :busy?

Core    = import('./core')
IO      = import('./io')

@size = 4

def process(&block)
  
  setup unless @task_queue
  EV.ref
  Core.promise { |p| @task_queue << [block, p] }
end

def size=(size)
  @size = size
end

def busy?
  !@queue.empty?
end

def setup
  @task_queue = ::Queue.new
  @resolve_queue = ::Queue.new

  @async_watcher = EV::Async.new { resolve_from_queue }
  EV.unref

  @threads = (1..@size).map { Thread.new { thread_loop } }
end

def resolve_from_queue
  while !@resolve_queue.empty?
    (promise, result, error) = @resolve_queue.pop(true)

    error ? promise.reject(error) : promise.resolve(result)
    EV.unref
  end
end

def thread_loop
  loop { run_queued_task }
end

def run_queued_task
  (block, promise) = @task_queue.pop
  result = block.()
  @resolve_queue << [promise, result]
  @async_watcher.signal!
rescue StandardError=> e
  @resolve_queue << [promise, nil, e]
  @async_watcher.signal!
end
