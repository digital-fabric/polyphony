# frozen_string_literal: true

export_default :Coprocess

import('../extensions/kernel')

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

  def run
    uncaught_exception = nil
    calling_fiber = Fiber.current

    @fiber = Fiber.new { execute }
    @ran = true
    @fiber.schedule
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
    # e.cleanup_backtrace(Fiber.current.backtrace)
    # if (backtrace = Fiber.current.backtrace)
    #   e.set_backtrace(e.backtrace + backtrace)
    # end
  ensure
    @@list.delete(@fiber)
    @fiber.coprocess = nil
    @fiber = nil
    @awaiting_fiber&.schedule @result
    @when_done&.()

    if uncaught_exception && !@awaiting_fiber
      $stdout.orig_puts "uncaught_exception: #{@result.inspect}"
    end

    suspend

    # # if result is an error and nobody's waiting on us, we need to raise it
    # # raise @result if @result.is_a?(Exception) && !@awaiting_fiber
    # if uncaught_exception && !@awaiting_fiber
    #   if Fiber.main == Fiber.current
    #     raise @result
    #   # elsif calling_fiber.alive?
    #   #   calling_fiber.transfer @result
    #   else
    #     Fiber.main.transfer @result
    #   end
    # end

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
