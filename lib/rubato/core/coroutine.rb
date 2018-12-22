# frozen_string_literal: true

export_default :Coroutine

FiberPool   = import('./fiber_pool')
Exceptions  = import('./exceptions')

# Encapsulates an asynchronous task
class Coroutine
  attr_reader :result, :fiber


  def initialize(&block)
    @block = block
  end

  def run(&block2)
    @fiber = FiberPool.spawn do
      @fiber.coroutine = self
      @result = (@block || block2).call(self)
    rescue Exceptions::MoveOn, Exceptions::Stop => e
      @result = e.value
    ensure
      @fiber.coroutine = nil
      @fiber = nil
      @awaiting_fiber&.resume @result
      @when_done&.()
    end

    @ran = true
    EV.next_tick { @fiber.resume }
    self
  end

  def <<(o)
    @queue ||= []
    @queue << o
    EV.next_tick { @fiber&.resume if @receive_waiting } if @receive_waiting
    EV.snooze
  end

  def receive
    @receive_waiting = true
    EV.next_tick { @fiber&.resume } if @queue && @queue.size > 0
    suspend
    @queue.shift
  ensure
    @receive_waiting = nil
  end

  def running?
    @fiber
  end

  # Kernel.await expects the given argument / block to be a callable, so #call
  # in fact waits for the coroutine to finish
  def await
    run unless @ran
    if @fiber
      @awaiting_fiber = Fiber.current
      suspend
    else
      @result
    end
  ensure
    # if awaiting was interrupted and the coroutine is still running, we need to stop it
    if @fiber
      EV.next_tick { @fiber&.resume(Exceptions::MoveOn.new) }
      suspend
    end
  end

  def when_done(&block)
    @when_done = block
  end

  def interrupt(value = Exceptions::MoveOn.new)
    @fiber&.resume(value)
  end

  def cancel!
    interrupt(Exceptions::Cancel.new)
  end

  def self.current
    Fiber.current.coroutine
  end
end