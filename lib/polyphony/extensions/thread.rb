# frozen_string_literal: true

require_relative '../core/exceptions'

# Thread extensions
class ::Thread
  attr_reader :main_fiber, :result

  alias_method :orig_initialize, :initialize
  def initialize(*args, &block)
    @join_wait_queue = []
    @finalization_mutex = Mutex.new
    @args = args
    @block = block
    orig_initialize { execute }
  end

  def execute
    # backend must be created in the context of the new thread, therefore it
    # cannot be created in Thread#initialize
    @backend = Polyphony::Backend.new
    setup
    @ready = true
    result = @block.(*@args)
  rescue Polyphony::MoveOn, Polyphony::Terminate => e
    result = e.value
  rescue Exception => e
    result = e
  ensure
    @ready = true
    finalize(result)
  end

  attr_accessor :backend

  def setup
    @main_fiber = Fiber.current
    @main_fiber.setup_main_fiber
    setup_fiber_scheduling
  end

  def finalize(result)
    unless Fiber.current.children.empty?
      Fiber.current.shutdown_all_children
    end
    @finalization_mutex.synchronize do
      @terminated = true
      @result = result
      signal_waiters(result)
    end
    @backend.finalize
  end

  def signal_waiters(result)
    @join_wait_queue.each { |w| w.signal(result) }
  end

  alias_method :orig_join, :join
  def join(timeout = nil)
    watcher = Fiber.current.auto_watcher

    @finalization_mutex.synchronize do
      if @terminated
        @result.is_a?(Exception) ? (raise @result) : (return @result)
      else
        @join_wait_queue << watcher
      end
    end
    timeout ? move_on_after(timeout) { watcher.await } : watcher.await
  end
  alias_method :await, :join

  alias_method :orig_raise, :raise
  def raise(error = nil)
    Thread.pass until @main_fiber
    error = RuntimeError.new if error.nil?
    error = RuntimeError.new(error) if error.is_a?(String)
    error = error.new if error.is_a?(Class)

    sleep 0.0001 until @ready
    main_fiber&.raise(error)
  end

  alias_method :orig_kill, :kill
  def kill
    return if @terminated

    raise Polyphony::Terminate
  end

  alias_method :orig_inspect, :inspect
  def inspect
    return orig_inspect if self == Thread.main

    state = status || 'dead'
    "#<Thread:#{object_id} #{location} (#{state})>"
  end
  alias_method :to_s, :inspect

  def location
    @block.source_location.join(':')
  end

  def <<(value)
    main_fiber << value
  end
  alias_method :send, :<<
end
