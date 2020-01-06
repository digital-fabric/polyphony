# frozen_string_literal: true

export_default :CancelScope

require 'fiber'

Exceptions = import('./exceptions')

# A cancellation scope that can be used to cancel an asynchronous task
class CancelScope
  def initialize(opts = {}, &block)
    @opts = opts
    @fibers = []
    start_timeout_waiter if @opts[:timeout]
    call(&block) if block
  end

  def error_class
    @opts[:mode] == :cancel ? Exceptions::Cancel : Exceptions::MoveOn
  end

  def cancel!
    @cancelled = true
    @fibers.each do |f|
      f.cancelled = true
      f.schedule error_class.new(self, @opts[:value])
    end
    @on_cancel&.()
  end

  def start_timeout_waiter
    @timeout_waiter = spin do
      sleep @opts[:timeout]
      @timeout_waiter = nil
      cancel!
    end
  end

  def stop_timeout_waiter
    return unless @timeout_waiter

    @timeout_waiter.stop
    @timeout_waiter = nil
  end

  def reset_timeout
    return unless @timeout_waiter

    @timeout_waiter.stop
    start_timeout_waiter
  end

  # def disable
  #   @timeout&.stop
  # end

  def call
    fiber = Fiber.current
    @fibers << fiber
    fiber.cancelled = nil
    yield self
  rescue Exceptions::MoveOn => e
    e.scope == self ? e.value : raise(e)
  ensure
    @fibers.delete fiber
    stop_timeout_waiter if @fibers.empty? && @timeout_waiter
  end

  def on_cancel(&block)
    @on_cancel = block
  end

  def cancelled?
    @cancelled
  end
end
