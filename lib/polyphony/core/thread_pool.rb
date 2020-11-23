# frozen_string_literal: true

require 'etc'

module Polyphony
  # Implements a pool of threads
  class ThreadPool
    attr_reader :size

    def self.process(&block)
      @default_pool ||= new
      @default_pool.process(&block)
    end

    def self.reset
      return unless @default_pool

      @default_pool.stop
      @default_pool = nil
    end

    def initialize(size = Etc.nprocessors)
      @size = size
      @task_queue = Polyphony::Queue.new
      @threads = (1..@size).map { Thread.new { thread_loop } }
    end

    def process(&block)
      setup unless @task_queue

      watcher = Fiber.current.auto_watcher
      @task_queue << [block, watcher]
      watcher.await
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
      while true
        run_queued_task
      end
    end

    def run_queued_task
      (block, watcher) = @task_queue.shift
      result = block.()
      watcher&.signal(result)
    rescue Exception => e
      watcher ? watcher.signal(e) : raise(e)
    end

    def stop
      @threads.each(&:kill)
      @threads.each(&:join)
    end
  end
end
