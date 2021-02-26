# frozen_string_literal: true

module Polyphony
  # Implements general-purpose throttling
  class Throttler
    def initialize(rate)
      @rate = rate_from_argument(rate)
      @min_dt = 1.0 / @rate
      @next_time = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
    end

    def call
      now = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
      delta = @next_time - now
      Polyphony.backend_sleep(delta) if delta > 0
      yield self

      while true
        @next_time += @min_dt
        break if @next_time > now
      end
    end
    alias_method :process, :call

    def stop
      @stop = true
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
end
