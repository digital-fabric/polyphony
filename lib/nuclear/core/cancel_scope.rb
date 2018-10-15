# frozen_string_literal: true

export_default :CancelScope

require 'fiber'

# Exception representing a cancellation that should raise an error
class ::Cancelled < ::Exception
  attr_reader :cancel_scope

  def initialize(cancel_scope, _value)
    @cancel_scope = cancel_scope
  end
end

# Exception representing a cancellation that should not raise an error
class ::MoveOn < ::Exception
  attr_reader :cancel_scope, :value

  def initialize(cancel_scope, value)
    @cancel_scope = cancel_scope
    @value = value
  end
end

# A cancellation scope that can be used to cancel an asynchronous task
class CancelScope
  attr_reader :opts

  def initialize(opts = {})
    @fiber = Fiber.current
    @opts = opts
    @cancel_error_class = opts[:mode] == :move_on ? ::MoveOn : ::Cancelled

    @timer = EV::Timer.new(opts[:timeout], 0) { cancel! } if @opts[:timeout]
  end

  # Runs the given block inside the cancellation scope
  # @return [any] result of given block
  def run
    yield(self)
  rescue MoveOn => e
    raise e unless e.cancel_scope == self
    nil
  ensure
    @timer&.stop
    @fiber.cancelled = false
  end

  # Cancels the current blocking operation by raising an exception in the
  # associated fiber.
  # @param value [any] value to pass if moving on
  # @return [void]
  def cancel!(value = nil)
    @fiber.cancelled = true
    @cancelled = true
    @fiber.resume @cancel_error_class.new(self, value)
  end

  # Returns true whether the scope was cancelled
  # @return [boolean]
  def cancelled?
    @cancelled
  end

  # Resets the timeout associated with the cancellation scope
  # @return [void]
  def reset_timer
    @timer.stop
    @timer.start
  end
end
