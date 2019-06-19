# frozen_string_literal: true

export_default :Coprocess

import('../extensions/kernel')

FiberPool   = import('./fiber_pool')
Exceptions  = import('./exceptions')

# Encapsulates an asynchronous task
class Coprocess
  @@list = {}

  def self.list
    @@list
  end

  def self.count
    @@list.size
  end

  attr_reader :result, :fiber

  def initialize(fiber = nil, &block)
    @fiber = fiber
    @block = block
  end

  def run(&block2)
    @caller = caller if Exceptions.debug
    uncaught_exception = nil

    @fiber = FiberPool.run do
      @@list[@fiber] = self
      @fiber.coprocess = self
      @result = (@block || block2).call(self)
    rescue Exceptions::MoveOn, Exceptions::Stop => e
      @result = e.value
    rescue Exception => e
      e.cleanup_backtrace(@caller) if Exceptions.debug
      @result = e
      uncaught_exception = true
    ensure
      @@list.delete(@fiber)
      @fiber.coprocess = nil
      @fiber = nil
      @awaiting_fiber&.schedule @result
      @when_done&.()

      # if result is an error and nobody's waiting on us, we need to raise it
      # raise @result if @result.is_a?(Exception) && !@awaiting_fiber
      if uncaught_exception && @result.is_a?(Exception) && !@awaiting_fiber
        if Fiber.main == Fiber.current
          raise @result
        else
          Fiber.main.transfer @result
        end
      end
    end

    @ran = true
    @fiber.schedule
    self
  end

  def <<(o)
    @mailbox ||= []
    @mailbox << o
    @fiber&.schedule if @receive_waiting
    snooze
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

  def alive?
    @fiber
  end

  # Kernel.await expects the given argument / block to be a callable, so #call
  # in fact waits for the coprocess to finish
  def await
    run unless @ran
    if @fiber
      @awaiting_fiber = Fiber.current
      suspend
    else
      @result
    end
  ensure
    # if awaiting was interrupted and the coprocess is still running, we need to stop it
    if @fiber
      @fiber&.schedule(Exceptions::MoveOn.new)
      suspend
    end
  end
  alias_method :join, :await

  def when_done(&block)
    @when_done = block
  end

  def resume(value = nil)
    @fiber&.schedule(value)
  end

  def interrupt(value = nil)
    @fiber&.schedule(Exceptions::MoveOn.new(nil, value))
  end
  alias_method :stop, :interrupt

  def cancel!
    @fiber&.schedule(Exceptions::Cancel.new)
  end

  def self.current
    Fiber.current.coprocess
  end
end
