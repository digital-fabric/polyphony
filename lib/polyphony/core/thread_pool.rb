# frozen_string_literal: true

require 'etc'

module Polyphony
  
  # Implements a pool of threads
  class ThreadPool
  
    # The pool size.
    attr_reader :size

    # Runs the given block on an available thread from the default thread pool.
    #
    # @yield [] given block
    # @return [any] return value of given block
    def self.process(&block)
      @default_pool ||= new
      @default_pool.process(&block)
    end

    # Resets the default thread pool.
    #
    # @return [void]
    def self.reset
      return unless @default_pool

      @default_pool.stop
      @default_pool = nil
    end

    # Initializes the thread pool. The pool size defaults to the number of
    # available CPU cores.
    #
    # @param size [Integer] number of threads in pool
    def initialize(size = Etc.nprocessors)
      @size = size
      @task_queue = Polyphony::Queue.new
      @threads = (1..@size).map { Thread.new { thread_loop } }
    end

    # Runs the given block on an available thread from the pool.
    #
    # @yield [] given block
    # @return [any] return value of block
    def process(&block)
      setup unless @task_queue

      watcher = Fiber.current.auto_watcher
      @task_queue << [block, watcher]
      watcher.await
    end

    # Adds a task to be performed asynchronously on a thread from the pool. This
    # method does not block. The task will be performed once a thread becomes
    # available.
    #
    # @yield [] given block
    # @return [Polyphony::ThreadPool] self
    def cast(&block)
      setup unless @task_queue

      @task_queue << [block, nil]
      self
    end

    # Returns true if there are any currently running tasks, or any pending
    # tasks waiting for a thread to become available.
    #
    # @return [bool] true if the pool is busy
    def busy?
      !@task_queue.empty?
    end

    # Stops and waits for all threads in the queue to terminate.
    def stop
      @threads.each(&:kill)
      @threads.each(&:join)
    end

    private

    # Runs a processing loop on a worker thread.
    #
    # @return [void]
    def thread_loop
      while true
        run_queued_task
      end
    end

    # Runs the first queued task in the task queue.
    #
    # @return [void]
    def run_queued_task
      (block, watcher) = @task_queue.shift
      result = block.()
      watcher&.signal(result)
    rescue Exception => e
      watcher ? watcher.signal(e) : raise(e)
    end
  end
end
