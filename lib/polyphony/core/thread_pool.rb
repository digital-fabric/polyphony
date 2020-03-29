# frozen_string_literal: true

export_default :ThreadPool

require 'etc'

# Implements a pool of threads
class ThreadPool
  attr_reader :size

  def self.process(&block)
    @default_pool ||= new
    @default_pool.process(&block)
  end

  def initialize(size = Etc.nprocessors)
    @size = size
    @task_queue = ::Queue.new
    @threads = (1..@size).map { Thread.new { thread_loop } }
  end

  def process(&block)
    setup unless @task_queue

    async = Fiber.current.auto_async
    @task_queue << [block, async]
    async.await
  end

  def cast(&block)
    setup unless @task_queue

    @task_queue << [block, nil]
    self
  end

  def busy?
    !@task_queue.empty?
  end

  def thread_loop
    loop { run_queued_task }
  end

  def run_queued_task
    (block, watcher) = @task_queue.pop
    result = block.()
    watcher&.signal(result)
  rescue Exception => e
    watcher ? watcher.signal(e) : raise(e)
  end
end
