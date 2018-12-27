# frozen_string_literal: true

export_default :Coroutine

import('../extensions/kernel')

FiberPool   = import('./fiber_pool')
Exceptions  = import('./exceptions')

# Encapsulates an asynchronous task
class Coroutine
  attr_reader :result, :fiber


  def initialize(fiber = nil, &block)
    @fiber = fiber
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
      @awaiting_fiber&.schedule @result
      @when_done&.()
    end

    @ran = true
    @fiber.schedule
    self
  end

  def <<(o)
    @mailbox ||= []
    @mailbox << o
    @fiber&.schedule if @receive_waiting
    EV.snooze
  end

  def receive
    EV.ref
    @receive_waiting = true
    @fiber&.schedule if @mailbox && @mailbox.size > 0
    suspend
    @mailbox.shift
  ensure
    EV.unref
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
      @fiber&.schedule(Exceptions::MoveOn.new)
      puts "@fiber: #{@fiber.inspect}"
      puts "reactor: #{EV.reactor_fiber.inspect}"
      suspend
    end
  end

  def when_done(&block)
    @when_done = block
  end

  def interrupt(value = Exceptions::MoveOn.new)
    @fiber&.schedule(value)
  end

  def cancel!
    interrupt(Exceptions::Cancel.new)
  end

  def self.current
    Fiber.current.coroutine
  end
end
