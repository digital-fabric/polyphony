# frozen_string_literal: true

export :process, :setup, :size=, :busy?

@size = 10

def process(&block)
  setup unless @task_queue

  proc { start_task_on_thread(block) }
end

def start_task_on_thread(block)
  EV.ref
  @task_queue << [block, Fiber.current]
  suspend
ensure
  EV.unref
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
  until @resolve_queue.empty?
    (fiber, result) = @resolve_queue.pop(true)
    fiber.resume result unless fiber.cancelled
  end
end

def thread_loop
  loop { run_queued_task }
end

def run_queued_task
  (block, fiber) = @task_queue.pop
  result = block.()
  @resolve_queue << [fiber, result]
  @async_watcher.signal!
rescue Exception => e
  @resolve_queue << [fiber, e]
  @async_watcher.signal!
end
