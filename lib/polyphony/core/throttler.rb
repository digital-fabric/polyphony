# frozen_string_literal: true

export_default :Throttler

# Implements general-purpose throttling
class Throttler
  def initialize(rate)
    @rate = rate_from_argument(rate)
    @min_dt = 1.0 / @rate
  end

  def call(&block)
    @timer ||= Gyro::Timer.new(0, @min_dt)
    @timer.await
    block.call(self)
  end
  alias_method :process, :call

  def stop
    @timer&.stop
  end

  private

  def rate_from_argument(arg)
    return arg if arg.is_a?(Numeric)

    if arg.is_a?(Hash)
      return 1.0 / arg[:interval] if arg[:interval]
      return arg[:rate] if arg[:rate]
    end
    raise "Invalid rate argument #{arg.inspect}"
  end
end
