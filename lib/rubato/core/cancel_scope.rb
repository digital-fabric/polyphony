# frozen_string_literal: true

export_default :CancelScope

require 'fiber'

Exceptions = import('./exceptions')

# A cancellation scope that can be used to cancel an asynchronous task
class CancelScope
  def initialize(opts = {})
    @opts = opts
    @error_class = @opts[:mode] == :cancel ? Exceptions::Cancel : Exceptions::MoveOn
  end

  def cancel!
    @fiber.cancelled = true
    @fiber.resume @error_class.new(self, @opts[:value])
  end

  def start_timeout
    @timeout = EV::Timer.new(@opts[:timeout], 0)
    @timeout.start { cancel! }
  end

  def reset_timeout
    @timeout.reset
  end

  def call
    start_timeout if @opts[:timeout]
    @fiber = Fiber.current
    yield self
  rescue Exceptions::MoveOn => e
    e.scope == self ? e.value : raise(e)
  ensure
    @timeout&.stop
  end
end
