# frozen_string_literal: true

Exceptions = import '../core/exceptions'

# Thread extensions
class ::Thread
  attr_reader :main_fiber

  alias_method :orig_initialize, :initialize
  def initialize(*args, &block)
    @join_wait_queue = Gyro::Queue.new
    orig_initialize do
      setup_fiber_scheduling
      block.(*args)
      signal_waiters
    end
  end

  def signal_waiters
    @join_wait_queue.shift_each { |w| w.signal!(self) }
  end

  alias_method :orig_join, :join
  def join(timeout = nil)
    return unless alive?

    async = Gyro::Async.new
    @join_wait_queue << async

    if timeout
      move_on_after(timeout) { async.await }
    else
      async.await
    end
  end
end
