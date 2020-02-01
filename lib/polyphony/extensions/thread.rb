# frozen_string_literal: true

Exceptions = import '../core/exceptions'

# Thread extensions
class ::Thread
  @@join_queue_mutex = Mutex.new

  attr_reader :main_fiber

  alias_method :orig_initialize, :initialize
  def initialize(*args, &block)
    @join_wait_queue = Gyro::Queue.new
    @block = block
    orig_initialize do
      Fiber.current.setup_main_fiber
      setup_fiber_scheduling
      block.(*args)
    ensure
      signal_waiters
      stop_event_selector
    end
  end

  def signal_waiters
    @join_wait_queue.shift_each { |w| w.signal!(self) }
  end

  alias_method :orig_join, :join
  def join(timeout = nil)
    async = Gyro::Async.new
    @@join_queue_mutex.synchronize do
      return unless alive?

      @join_wait_queue << async
    end

    if timeout
      move_on_after(timeout) { async.await }
    else
      async.await
    end
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
