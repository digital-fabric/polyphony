# frozen_string_literal: true

module Polyphony

  # Implements a common timer for running multiple timeouts. This class may be
  # used to reduce the timer granularity in case a large number of timeouts is
  # used concurrently. This class basically provides the same methods as global
  # methods concerned with timeouts, such as `#cancel_after`, `#every` etc.
  class Timer

    # Initializes a new timer with the given resolution.
    #
    # @param tag [any] tag to use for the timer's fiber
    # @param resolution: [Number] timer granularity in seconds or fractions thereof
    def initialize(tag = nil, resolution:)
      @fiber = spin_loop(tag, interval: resolution) { update }
      @timeouts = {}
    end

    # Stops the timer's associated fiber.
    #
    # @return [Polyphony::Timer] self
    def stop
      @fiber.stop
      self
    end

    # Sleeps for the given duration.
    #
    # @param duration [Number] sleep duration in seconds
    # @return [void]
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

    # Spins up a fiber that will run the given block after sleeping for the
    # given delay.
    #
    # @param delay [Number] delay in seconds before running the given block
    # @param &block [Proc] block to run
    # @return [Fiber] spun fiber
    def after(interval, &block)
      spin do
        self.sleep interval
        block.()
      end
    end

    # Runs the given block in an infinite loop with a regular interval between
    # consecutive iterations.
    #
    # @param interval [Number] interval between consecutive iterations in seconds
    # @param &block [Proc] block to run
    # @return [void]
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

    # call-seq:
    #   timer.cancel_after(interval) { ... }
    #   timer.cancel_after(interval, with_exception: exception) { ... }
    #   timer.cancel_after(interval, with_exception: [klass, message]) { ... }
    #   timer.cancel_after(interval) { |timeout| ... }
    #   timer.cancel_after(interval, with_exception: exception) { |timeout| ... }
    #   timer.cancel_after(interval, with_exception: [klass, message]) { |timeout| ... }
    #
    # Runs the given block after setting up a cancellation timer for
    # cancellation. If the cancellation timer elapses, the execution will be
    # interrupted with an exception defaulting to `Polyphony::Cancel`.
    #
    # This method should be used when a timeout should cause an exception to be
    # propagated down the call stack or up the fiber tree.
    #
    # Example of normal use:
    #
    #   def read_from_io_with_timeout(io)
    #     timer.cancel_after(10) { io.read }
    #   rescue Polyphony::Cancel
    #     nil
    #   end
    #
    # The timeout period can be reset using `Timer#reset`, as shown in the
    # following example:
    #
    #   timer.cancel_after(10) do
    #     loop do
    #       msg = socket.gets
    #       timer.reset
    #       handle_msg(msg)
    #     end
    #   end
    #
    # @param interval [Number] timout in seconds
    # @param with_exception: [Class, Exception] exception or exception class
    # @param &block [Proc] block to execute
    # @return [any] block's return value
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

    # call-seq:
    #   timer.move_on_after(interval) { ... }
    #   timer.move_on_after(interval, with_value: value) { ... }
    #   timer.move_on_after(interval) { |canceller| ... }
    #   timer.move_on_after(interval, with_value: value) { |canceller| ... }
    #
    # Runs the given block after setting up a cancellation timer for
    # cancellation. If the cancellation timer elapses, the execution will be
    # interrupted with a `Polyphony::MoveOn` exception, which will be rescued,
    # and with cause the operation to return the given value.
    #
    # This method should be used when a timeout is to be handled locally,
    # without generating an exception that is to propagated down the call stack
    # or up the fiber tree.
    #
    # Example of normal use:
    #
    #   timer.move_on_after(10) {
    #     sleep 60
    #     42
    #   } #=> nil
    #
    #   timer.move_on_after(10, with_value: :oops) {
    #     sleep 60
    #     42
    #   } #=> :oops
    #
    # The timeout period can be reset using `Timer#reset`, as shown in the
    # following example:
    #
    #   timer.move_on_after(10) do
    #     loop do
    #       msg = socket.gets
    #       timer.reset
    #       handle_msg(msg)
    #     end
    #   end
    #
    # @param interval [Number] timout in seconds
    # @param with_value: [any] return value in case of timeout
    # @param &block [Proc] block to execute
    # @return [any] block's return value
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

    # Resets the timeout for the current fiber.
    #
    # @return [void]
    def reset
      record = @timeouts[Fiber.current]
      return unless record

      record[:target_stamp] = now + record[:interval]
    end

    private

    # Returns the current monotonic clock value.
    #
    # @return [Number] monotonic clock value in seconds
    def now
      ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
    end

    # Converts a timeout record's exception spec to an exception instance.
    #
    # @param record [Array, Class, Exception, String] exception spec
    # @return [Exception] exception instance
    def timeout_exception(record)
      case (exception = record[:exception])
      when Array
        exception[0].new(exception[1])
      when Class
        exception.new
      when Exception
        exception
      else
        RuntimeError.new(exception)
      end
    end

    # Runs a timer iteration, invoking any timeouts that are due.
    #
    # @return [void]      
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
