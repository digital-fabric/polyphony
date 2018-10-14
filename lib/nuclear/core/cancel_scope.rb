# frozen_string_literal: true

export_default :CancelScope

require 'fiber'

class ::Cancelled < ::Exception
  attr_reader :cancel_scope

  def initialize(cancel_scope, _value)
    @cancel_scope = cancel_scope
  end
end

class ::MoveOn < ::Exception
  attr_reader :cancel_scope, :value
  
  def initialize(cancel_scope, value)
    @cancel_scope = cancel_scope
    @value = value
  end
end

class CancelScope
  attr_reader :opts

  def initialize(opts = {}, &block)
    @fiber = Fiber.current
    @opts = opts
    @cancel_error_class = opts[:mode] == :move_on ? ::MoveOn : ::Cancelled

    if @opts[:timeout]
      @timer = EV::Timer.new(opts[:timeout], 0) { cancel! }
    end
  end

  def run
    # @fiber.cancelled = false
    yield(self)
  rescue MoveOn => e
    raise e unless e.cancel_scope == self
    nil
  ensure
    @timer&.stop
    @fiber.cancelled = false
  end

  def cancel!(value = nil)
    @fiber.cancelled = true
    @cancelled = true
    @fiber.resume @cancel_error_class.new(self, value)
  end

  def cancelled?
    @cancelled
  end

  def reset_timer
    @timer.stop
    @timer.start
  end
end