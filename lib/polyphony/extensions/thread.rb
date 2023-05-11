# frozen_string_literal: true

require_relative '../core/exceptions'

# Thread extensions
class ::Thread
  attr_reader :main_fiber, :result
  attr_accessor :backend

  # @!visibility private
  alias_method :orig_initialize, :initialize

  # Initializes the thread.
  # @param args [Array] arguments to pass to thread block
  def initialize(*args, &block)
    @join_wait_queue = []
    @finalization_mutex = Mutex.new
    @args = args
    @block = block
    orig_initialize { execute }
  end

  # Sets up the thread and its main fiber.
  #
  # @return [Thread] self
  def setup
    @main_fiber = Fiber.current
    @main_fiber.setup_main_fiber
    setup_fiber_scheduling
    self
  end

  # @!visibility private
  alias_method :orig_join, :join

  # Waits for the thread to terminate and returns its return value. If the
  # thread terminated with an uncaught exception, it is propagated to the
  # waiting fiber. If a timeout interval is specified, the thread will be
  # terminated without propagating the timeout exception.
  #
  # @param timeout [Number] timeout interval
  # @return [any] thread's return value
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

  # @!visibility private
  alias_method :orig_raise, :raise

  # Raises an exception in the context of the thread. If no exception is given,
  # a `RuntimeError` is raised.
  #
  # @param error [Exception, Class, nil] exception spec
  def raise(error = nil)
    Thread.pass until @main_fiber
    error = RuntimeError.new if error.nil?
    error = RuntimeError.new(error) if error.is_a?(String)
    error = error.new if error.is_a?(Class)

    sleep 0.0001 until @ready
    main_fiber&.raise(error)
  end

  # @!visibility private
  alias_method :orig_kill, :kill

  # Terminates the thread.
  #
  # @return [Thread] self
  def kill
    return self if @terminated

    raise Polyphony::Terminate
    self
  end

  # @!visibility private
  alias_method :orig_inspect, :inspect

  # Returns a string representation of the thread for debugging purposes.
  #
  # @return [String] string representation
  def inspect
    return orig_inspect if self == Thread.main

    state = status || 'dead'
    "#<Thread:#{object_id} #{location} (#{state})>"
  end
  alias_method :to_s, :inspect

  # Returns the source location of the thread's block.
  #
  # @return [String] source location
  def location
    @block.source_location.join(':')
  end

  # Sends a message to the thread's main fiber.
  #
  # @param msg [any] message
  # @return [Fiber] main fiber
  def <<(msg)
    main_fiber << msg
  end
  alias_method :send, :<<

  # Sets the idle GC period for the thread's backend.
  #
  # @param period [Number] GC period in seconds
  # @return [Number] GC period
  def idle_gc_period=(period)
    backend.idle_gc_period = period
  end

  # Sets the idle handler for the thread's backend.
  #
  # @return [Proc] idle handler
  def on_idle(&block)
    backend.idle_proc = block
  end

  private

  # Runs the thread's block, handling any uncaught exceptions.
  #
  # @return [any] thread result value
  def execute
    # backend must be created in the context of the new thread, therefore it
    # cannot be created in Thread#initialize
    raise_error = false
    begin
      @backend = Polyphony::Backend.new
    rescue Exception => e
      raise_error = true
      raise e
    end
    setup
    @ready = true
    result = @block.(*@args)
  rescue Polyphony::MoveOn, Polyphony::Terminate => e
    result = e.value
  rescue Exception => e
    raise_error ? (raise e) : (result = e)
  ensure
    @ready = true
    finalize(result)
  end

  # Finalizes the thread.
  #
  # @param result [any] thread's return value
  def finalize(result)
    unless Fiber.current.children.empty?
      Fiber.current.shutdown_all_children
    end
    @finalization_mutex.synchronize do
      @terminated = true
      @result = result
      signal_waiters(result)
    end
    @backend&.finalize
  end

  # Signals all fibers waiting for the thread to terminate.
  #
  # @param result [any] thread's return value
  def signal_waiters(result)
    @join_wait_queue.each { |w| w.signal(result) }
  end
end
