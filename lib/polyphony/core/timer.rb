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

    def sleep(duration)
      fiber = Fiber.current
      @timeouts[fiber] = {
        interval: duration,
        target_stamp: now + duration
      }
      Polyphony.backend_wait_event(true)
    ensure
      @timeouts.delete(fiber)
    end

    def after(interval, &block)
      spin do
        self.sleep interval
        block.()
      end
    end

    def every(interval)
      fiber = Fiber.current
      @timeouts[fiber] = {
        interval: interval,
        target_stamp: now + interval,
        recurring: true
      }
      while true
        Polyphony.backend_wait_event(true)
        yield
      end
    ensure
      @timeouts.delete(fiber)
    end
  
    def cancel_after(interval, with_exception: Polyphony::Cancel)
      fiber = Fiber.current
      @timeouts[fiber] = {
        interval: interval,
        target_stamp: now + interval,
        exception: with_exception
      }
      yield
    ensure
      @timeouts.delete(fiber)
    end

    def move_on_after(interval, with_value: nil)
      fiber = Fiber.current
      @timeouts[fiber] = {
        interval: interval,
        target_stamp: now + interval,
        exception: [Polyphony::MoveOn, with_value]
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
  
      record[:target_stamp] = now + record[:interval]
    end

    private

    def now
      ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
    end

    def timeout_exception(record)
      case (exception = record[:exception])
      when Array
        exception[0].new(exception[1])
      when Class
        exception.new
      else
        RuntimeError.new(exception)
      end
    end

    def update
      return if @timeouts.empty?

      @timeouts.each do |fiber, record|
        next if record[:target_stamp] > now

        value = record[:exception] ? timeout_exception(record) : record[:value]
        fiber.schedule value

        next unless record[:recurring]

        while record[:target_stamp] <= now
          record[:target_stamp] += record[:interval]
        end
      end
    end
  end
end
