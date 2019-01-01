# frozen_string_literal: true

export_default :Throttler

class Throttler
  def initialize(rate)
    @rate = rate_from_argument(rate)
    @min_dt = 1.0 / @rate
    @last_iteration_clock = clock - @min_dt
  end

  def clock
    ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
  end

  def call(&block)
    now = clock
    dt = now - @last_iteration_clock
    if dt < @min_dt
      sleep(@min_dt - dt)
    end
    @last_iteration_clock = dt > @min_dt ? now : @last_iteration_clock + @min_dt
    block.call(self)
  end

  alias_method :process, :call

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
