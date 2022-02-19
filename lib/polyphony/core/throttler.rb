# frozen_string_literal: true

module Polyphony
  # Implements general-purpose throttling
  class Throttler

    # Initializes a throttler instance with the given rate.
    #
    # @param rate [Number] throttler rate in times per second
    def initialize(rate)
      @rate = rate_from_argument(rate)
      @min_dt = 1.0 / @rate
      @next_time = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
    end

    # Invokes the throttler with the given block. The throttler will
    # automatically introduce a delay to keep to the maximum specified rate.
    # The throttler instance is passed to the given block.
    #
    # call-seq:
    #   throttler.call { ... }
    #   throttler.process { ... }
    #
    # @return [any] given block's return value
    def call
      now = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
      delta = @next_time - now
      Polyphony.backend_sleep(delta) if delta > 0
      result = yield self

      while true
        @next_time += @min_dt
        break if @next_time > now
      end
      
      result
    end
    alias_method :process, :call

    private

    # Converts the given argument to a rate. If a hash is given, the throttler's
    # rate is computed from the value of either the `:interval` or `:rate` keys.
    #
    # @param arg [Number, Hash] rate argument
    # @return [Number] rate in times per second
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
