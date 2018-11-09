# frozen_string_literal: true

export_default :Task

FiberPool   = import('./fiber_pool')
Exceptions  = import('./exceptions')

# Encapsulates an asynchronous task
class Task
  attr_reader   :result
  attr_accessor :supervisor

  def initialize(&block)
    @block = block
  end

  # @return [void]
  def start
    @result = nil
    EV.next_tick { FiberPool.spawn { run } }
    self
  end

  def await(&block)
    @block ||= block
    @awaiting_fiber = Fiber.current
    start unless @fiber
    suspend
  rescue Exceptions::Stopped, Exceptions::Cancelled => e
    @result = e
    @awaiting_fiber = nil
    @fiber&.resume(e)
    raise e
  end

  def run
    # result will be set to an exception if the task has been cancelled or
    # stopped after having been scheduled but before actually running
    return if @result

    @fiber = Fiber.current
    @result = @block.()
    @awaiting_fiber&.resume(@result)
  rescue Exceptions::Stopped
    @awaiting_fiber&.resume(nil)
  rescue Exception => e
    @result = e
    if @awaiting_fiber
      @awaiting_fiber.resume(e)
    else
      raise(e) unless e.is_a?(Exceptions::Cancelled)
    end
  ensure
    @fiber = nil
    @supervisor&.task_stopped(self, @result)
  end

  def running?
    @fiber
  end

  def cancelled?
    @result.is_a?(Exceptions::Cancelled)
  end

  def stop!
    return unless @fiber

    @fiber.resume Exceptions::Stopped.new
  end

  def cancel!
    return unless @fiber

    @fiber.resume Exceptions::Cancelled.new
  end
end