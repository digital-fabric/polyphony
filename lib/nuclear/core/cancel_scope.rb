# frozen_string_literal: true

export_default :CancelScope

require 'fiber'

Exceptions = import('./exceptions')

# A cancellation scope that can be used to cancel an asynchronous task
class CancelScope
  attr_reader :opts

  def initialize(opts = {})
    @fiber = Fiber.current
    @opts = opts
    @cancel_error_class = opts[:mode] == :stop ?
      Exceptions::Stopped : Exceptions::Cancelled

    @timeout = EV::Timer.new(opts[:timeout], 0) if @opts[:timeout]
  end

  def on_cancel(&block)
    @on_cancel = block
  end

  # Runs the given block inside the cancellation scope
  # @return [any] result of given block
  def run
    @timeout&.start(&method(:cancel!))
    yield(self)
  rescue Exceptions::Stopped => e
    raise e unless e.scope == self
    nil
  ensure
    @timeout&.stop
    @fiber.cancelled = false
  end

  # Cancels the current blocking operation by raising an exception in the
  # associated fiber.
  # @param value [any] value to pass if moving on
  # @return [void]
  def cancel!(value = nil)
    @on_cancel&.call
    @fiber.cancelled = true
    @cancelled = true
    @fiber.resume @cancel_error_class.new(self)
  end

  # Returns true whether the scope was cancelled
  # @return [boolean]
  def cancelled?
    @cancelled
  end

  # Resets the timeout associated with the cancellation scope
  # @return [void]
  def reset_timeout
    @timeout.reset
  end
end
