# frozen_string_literal: true

export_default :Coprocess

import '../extensions/core'
Exceptions = import './exceptions'

# Encapsulates an asynchronous task
class Coprocess
  # inter-coprocess message passing
  module Messaging
    def <<(value)
      if @receive_waiting && @fiber
        @fiber&.schedule value
      else
        @queued_messages ||= []
        @queued_messages << value
      end
      snooze
    end

    def receive
      if !@queued_messages || @queued_messages&.empty?
        wait_for_message
      else
        value = @queued_messages.shift
        snooze
        value
      end
    end

    def wait_for_message
      Gyro.ref
      @receive_waiting = true
      suspend
    ensure
      Gyro.unref
      @receive_waiting = nil
    end
  end

  include Messaging

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

    @fiber = Fiber.new { execute }
    @fiber.schedule
    @ran = true
    self
  end

  def execute
    # uncaught_exception = nil
    @@list[@fiber] = self
    @fiber.coprocess = self
    @result = @block.call(self)
  rescue Exceptions::MoveOn => e
    @result = e.value
  rescue Exception => e
    uncaught_exception = true
    @result = e
  ensure
    finish_execution(uncaught_exception)
  end

  def finish_execution(uncaught_exception)
    @@list.delete(@fiber)
    @fiber.coprocess = nil
    @fiber = nil
    @awaiting_fiber&.schedule @result
    @when_done&.()

    return unless uncaught_exception && !@awaiting_fiber

    # if no awaiting fiber, raise any uncaught error by passing it to the
    # calling fiber, or to the root fiber if the calling fiber
    calling_fiber = @calling_fiber || Fiber.root
    calling_fiber.transfer @result
  end

  def alive?
    @fiber
  end

  def caller
    @fiber&.__caller__[2..]
  end

  def location
    caller[0]
  end

  # Kernel.await expects the given argument / block to be a callable, so #call
  # in fact waits for the coprocess to finish
  def await
    await_coprocess_result
  ensure
    # If the awaiting fiber has been transferred an exception, the awaited fiber
    # might still be running, so we need to stop it
    @fiber&.schedule(Exceptions::MoveOn.new)
  end
  alias_method :join, :await

  def await_coprocess_result
    run unless @ran
    if @fiber
      @awaiting_fiber = Fiber.current
      suspend
    else
      @result
    end
  end

  def when_done(&block)
    @when_done = block
  end

  def resume(value = nil)
    return unless @fiber

    @fiber.schedule(value)
    snooze
  end

  def interrupt(value = nil)
    return unless @fiber

    @fiber.schedule(Exceptions::MoveOn.new(nil, value))
    snooze
  end
  alias_method :stop, :interrupt

  def transfer(value = nil)
    @fiber&.schedule(value)
  end

  def cancel!
    return unless @fiber

    @fiber.schedule(Exceptions::Cancel.new)
    snooze
  end

  def self.current
    Fiber.current.coprocess
  end
end
