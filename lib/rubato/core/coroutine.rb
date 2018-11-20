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
      @result = (@block || block2).call(self)
    rescue Exceptions::MoveOn, Exceptions::Stop => e
      @result = e.value
    ensure
      @fiber = nil
      @awaiting_fiber&.resume @result
      @when_done&.()
    end

    @ran = true    
    EV.next_tick { @fiber.resume }
    self
  end

  def running?
    @fiber
  end

  # Kernel.await expects the given argument / block to be a callable, so #call
  # in fact waits for the coroutine to finish
  def call(&block)
    run(&block) unless @ran
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

  def to_proc
    -> { call }
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
end