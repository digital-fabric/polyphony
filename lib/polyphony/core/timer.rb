# frozen_string_literal: true

module Polyphony
  # Implements a common timer for running multiple timeouts
  class Timer
    def initialize(resolution:)
      @fiber = spin_loop(interval: resolution) { update }
      @timeouts = {}
    end

    def stop
      @fiber.stop
    end
  
    def cancel_after(duration, with_exception: Polyphony::Cancel)
      fiber = Fiber.current
      @timeouts[fiber] = {
        duration: duration,
        target_stamp: Time.now + duration,
        exception: with_exception
      }
      yield
    ensure
      @timeouts.delete(fiber)
    end

    def move_on_after(duration, with_value: nil)
      fiber = Fiber.current
      @timeouts[fiber] = {
        duration: duration,
        target_stamp: Time.now + duration,
        value: with_value
      }
      yield
    rescue Polyphony::MoveOn => e
      e.value
    ensure
      @timeouts.delete(fiber)
    end
  
    def reset
      record = @timeouts[Fiber.current]
      return unless record
  
      record[:target_stamp] = Time.now + record[:duration]
    end
  
    private

    def timeout_exception(record)
      case (exception = record[:exception])
      when Class then exception.new
      when Array then exception[0].new(exception[1])
      when nil then Polyphony::MoveOn.new(record[:value])
      else RuntimeError.new(exception)
      end
    end

    def update
      now = Time.now
      # elapsed = nil
      @timeouts.each do |fiber, record|
        next if record[:target_stamp] > now

        exception = timeout_exception(record)
        # (elapsed ||= []) << fiber
        fiber.schedule exception
      end
      # elapsed&.each { |f| @timeouts.delete(f) }
    end
  end
end
