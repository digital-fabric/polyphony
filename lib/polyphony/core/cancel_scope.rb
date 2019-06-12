# frozen_string_literal: true

export_default :CancelScope

require 'fiber'

Exceptions = import('./exceptions')

# A cancellation scope that can be used to cancel an asynchronous task
class CancelScope
  def initialize(opts = {})
    @opts = opts
    @error_class = (@opts[:mode] == :cancel) ?
      Exceptions::Cancel : Exceptions::MoveOn
  end

  def cancel!
    @cancelled = true
    @fiber.cancelled = true
    @fiber.transfer @error_class.new(self, @opts[:value])
  end

  def start_timeout
    @timeout = EV::Timer.new(@opts[:timeout], 0)
    @timeout.start { cancel! }
  end

  def reset_timeout
    @timeout.reset
  end

  def disable
    @timeout&.stop
  end

  def call
    start_timeout if @opts[:timeout]
    @fiber = Fiber.current
    @fiber.cancelled = nil
    yield self
  rescue Exceptions::MoveOn => e
    e.scope == self ? e.value : raise(e)
  ensure
    @timeout&.stop
    protect(&@when_cancelled) if @cancelled && @when_cancelled
  end

  def when_cancelled(&block)
    @when_cancelled = block
  end

  def cancelled?
    @cancelled
  end

  def protect(&block)
    @fiber.cancelled = false
    block.()
  ensure
    @fiber.cancelled = @cancelled
  end
end
