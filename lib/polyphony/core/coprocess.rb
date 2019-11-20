# frozen_string_literal: true

export_default :Coprocess

import '../extensions/kernel'

Exceptions  = import './exceptions'
FiberPool   = import './fiber_pool'

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

  def run
    @calling_fiber = Fiber.current

    @fiber = FiberPool.allocate { execute }
    @fiber.schedule
    @ran = true
    self
  end

  def execute
    @@list[@fiber] = self
    @fiber.coprocess = self
    @result = @block.call(self)
  rescue Exceptions::MoveOn, Exceptions::Stop => e
    @result = e.value
  rescue Exception => uncaught_exception
    @result = uncaught_exception
  ensure
    @@list.delete(@fiber)
    @fiber.coprocess = nil
    @fiber = nil
    @awaiting_fiber&.schedule @result
    @when_done&.()

    # the fiber pool will propagate the exception to the calling fiber
    raise uncaught_exception if uncaught_exception && !@awaiting_fiber

    suspend
  end

  def <<(o)
    @mailbox ||= []
    @mailbox << o
    @fiber&.schedule if @receive_waiting
    snooze
  end

  def receive
    Gyro.ref
    @receive_waiting = true
    @fiber&.schedule if @mailbox && @mailbox.size > 0
    suspend
    @mailbox.shift
  ensure
    Gyro.unref
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
    # if the awaited coprocess is still running, we need to stop it
    if @fiber
      @fiber.schedule(Exceptions::MoveOn.new)
      snooze
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
