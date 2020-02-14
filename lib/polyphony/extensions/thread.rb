# frozen_string_literal: true

Exceptions = import '../core/exceptions'

# Thread extensions
class ::Thread
  attr_reader :main_fiber

  alias_method :orig_initialize, :initialize
  def initialize(*args, &block)
    @join_wait_queue = Gyro::Queue.new
    @args = args
    @block = block
    orig_initialize { execute }
  end

  def execute
    setup
    result = @block.(*@args)
  rescue Exceptions::MoveOn, Exceptions::Terminate => e
    result = e.value
  rescue Exception => e
    result = e
  ensure
    finalize(result)
  end

  def setup
    @main_fiber = Fiber.current
    @main_fiber.setup_main_fiber
    setup_fiber_scheduling
  end

  def finalize(result)
    unless Fiber.current.children.empty?
      Fiber.current.terminate_all_children
      Fiber.current.await_all_children
    end
    signal_waiters(result)
    stop_event_selector
  end

  def signal_waiters(result)
    @join_wait_queue.shift_each { |w| w.signal!(result) }
  end

  alias_method :orig_join, :join
  def join(timeout = nil)
    if timeout
      move_on_after(timeout) { join_perform }
    else
      join_perform
    end
  end
  alias_method :await, :join

  alias_method :orig_raise, :raise
  def raise(error = nil)
    Thread.pass until @main_fiber
    error = RuntimeError.new if error.nil?
    error = RuntimeError.new(error) if error.is_a?(String)
    error = error.new if error.is_a?(Class)
    @main_fiber.raise(error)
  end

  alias_method :orig_kill, :kill
  def kill
    raise Exceptions::Terminate
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
