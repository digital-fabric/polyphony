# frozen_string_literal: true

require_relative '../extensions/core'
require_relative '../extensions/fiber'
require_relative './exceptions'
require_relative './throttler'

module Polyphony
  # Global API methods to be included in ::Object
  module GlobalAPI
    def after(interval, &block)
      spin do
        sleep interval
        block.()
      end
    end

    def cancel_after(interval, with_exception: Polyphony::Cancel, &block)
      if !block
        cancel_after_blockless_canceller(Fiber.current, interval, with_exception)
      elsif block.arity > 0
        cancel_after_with_block(Fiber.current, interval, with_exception, &block)
      else
        Thread.current.backend.timeout(interval, with_exception, &block)
      end
    end

    def cancel_after_blockless_canceller(fiber, interval, with_exception)
      spin do
        sleep interval
        exception = cancel_exception(with_exception)
        exception.__raising_fiber__ = nil
        fiber.schedule exception
      end
    end

    def cancel_after_with_block(fiber, interval, with_exception, &block)
      canceller = cancel_after_blockless_canceller(fiber, interval, with_exception)
      block.call(canceller)
    ensure
      canceller.stop
    end

    def cancel_exception(exception)
      case exception
      when Class then exception.new
      when Array then exception[0].new(exception[1])
      else RuntimeError.new(exception)
      end
    end

    def spin(tag = nil, &block)
      Fiber.current.spin(tag, caller, &block)
    end

    def spin_loop(tag = nil, rate: nil, &block)
      if rate
        Fiber.current.spin(tag, caller) do
          throttled_loop(rate, &block)
        end
      else
        Fiber.current.spin(tag, caller) { loop(&block) }
      end
    end

    def spin_scope
      raise unless block_given?
    
      spin do
        result = yield
        Fiber.current.await_all_children
        result
      end.await
    end

    def every(interval)
      next_time = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) + interval
      loop do
        now = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
        Thread.current.backend.sleep(next_time - now)
        yield
        loop do
          next_time += interval
          break if next_time > now
        end
      end
    end

    def move_on_after(interval, with_value: nil, &block)
      if !block
        move_on_blockless_canceller(Fiber.current, interval, with_value)
      elsif block.arity > 0
        move_on_after_with_block(Fiber.current, interval, with_value, &block)
      else
        Thread.current.backend.timeout(interval, nil, with_value, &block)
      end
    end

    def move_on_blockless_canceller(fiber, interval, with_value)
      spin do
        sleep interval
        fiber.schedule with_value
      end
    end

    def move_on_after_with_block(fiber, interval, with_value, &block)
      canceller = spin do
        sleep interval
        fiber.schedule Polyphony::MoveOn.new(with_value)
      end
      block.call(canceller)
    rescue Polyphony::MoveOn => e
      e.value
    ensure
      canceller.stop
    end

    def receive
      Fiber.current.receive
    end

    def receive_all_pending
      Fiber.current.receive_all_pending
    end

    def supervise(*args, &block)
      Fiber.current.supervise(*args, &block)
    end

    def sleep(duration = nil)
      return sleep_forever unless duration

      Thread.current.backend.sleep duration
    end

    def sleep_forever
      Thread.current.backend.wait_event(true)
    end

    def throttled_loop(rate = nil, **opts, &block)
      throttler = Polyphony::Throttler.new(rate || opts)
      if opts[:count]
        opts[:count].times { |_i| throttler.(&block) }
      else
        loop { throttler.(&block) }
      end
    ensure
      throttler&.stop
    end
  end
end

Object.include Polyphony::GlobalAPI
