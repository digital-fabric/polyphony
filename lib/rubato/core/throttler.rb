# frozen_string_literal: true

export_default :Throttler

class Throttler
  def initialize(rate)
    @rate = rate
    @min_dt = 1.0 / rate
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
end
