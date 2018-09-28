# frozen_string_literal: true

export :process, :setup, :size=, :busy?

Core    = import('./core')
IO      = import('./io')

@size = 4

def process(&block)
  setup unless @queue
  Core.promise { |p| @queue << [block, p] }
end

def size=(size)
  @size = size 
end

def busy?
  !@queue.empty?
end

def setup
  @queue = ::Queue.new

  @threads = (1..@size).map { Thread.new { thread_loop } }#.tap { |t| t.priority = 1 } }
end

def thread_loop
  loop { run_queued_task }
end

def run_queued_task
  (block, promise) = @queue.pop
  result = block.()
  Core.xthread_tick { promise.resolve(result) }
rescue StandardError=> e
  Core.xthread_tick { promise.reject(e) }
end
