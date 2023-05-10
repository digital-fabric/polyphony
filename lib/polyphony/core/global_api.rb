# frozen_string_literal: true

require_relative './throttler'

module Polyphony

  # Global API methods to be included in `::Object`
  module GlobalAPI

    # Spins up a fiber that will run the given block after sleeping for the
    # given delay.
    #
    # @param interval [Number] delay in seconds before running the given block
    # @return [Fiber] spun fiber
    def after(interval, &block)
      spin do
        sleep interval
        block.()
      end
    end

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
    #     cancel_after(10) { io.read }
    #   rescue Polyphony::Cancel
    #     nil
    #   end
    #
    # The timeout period can be reset by passing a block that takes a single
    # argument. The block will be provided with the canceller fiber. To reset
    # the timeout, use `Fiber#reset`, as shown in the following example:
    #
    #   cancel_after(10) do |timeout|
    #     loop do
    #       msg = socket.gets
    #       timeout.reset
    #       handle_msg(msg)
    #     end
    #   end
    #
    # @overload cancel_after(interval)
    #   @param interval [Number] timout in seconds
    #   @yield [Fiber] timeout fiber
    #   @return [any] block's return value
    # @overload cancel_after(interval, with_exception: exception)
    #   @param interval [Number] timout in seconds
    #   @param with_exception [Class, Exception] exception or exception class
    #   @yield [Fiber] timeout fiber
    #   @return [any] block's return value
    # @overload cancel_after(interval, with_exception: [klass, message])
    #   @param interval [Number] timout in seconds
    #   @param with_exception [Array] array containing class and message to use as exception
    #   @yield [Fiber] timeout fiber
    #   @return [any] block's return value
    def cancel_after(interval, with_exception: Polyphony::Cancel, &block)
      if block.arity > 0
        cancel_after_with_optional_reset(interval, with_exception, &block)
      else
        Polyphony.backend_timeout(interval, with_exception, &block)
      end
    end

    # Spins up a new fiber.
    #
    # @param tag [any] optional tag for the new fiber
    # @return [Fiber] new fiber
    def spin(tag = nil, &block)
      Fiber.current.spin(tag, caller, &block)
    end

    # Spins up a new fiber, running the given block inside an infinite loop. If
    # `rate:` or `interval:` parameters are given, the loop is throttled
    # accordingly.
    #
    # @param tag [any] optional tag for the new fiber
    # @param rate [Number, nil] loop rate (times per second)
    # @param interval [Number, nil] interval between consecutive iterations in seconds
    # @return [Fiber] new fiber
    def spin_loop(tag = nil, rate: nil, interval: nil, &block)
      if rate || interval
        Fiber.current.spin(tag, caller) do
          throttled_loop(rate: rate, interval: interval, &block)
        end
      else
        spin_loop_without_throttling(tag, caller, block)
      end
    end

    # Runs the given code, then waits for any child fibers of the current fibers
    # to terminate.
    #
    # @return [any] given block's return value
    def spin_scope(&block)
      raise unless block

      spin do
        result = yield
        Fiber.current.await_all_children
        result
      end.await
    end

    # Runs the given block in an infinite loop with a regular interval between
    # consecutive iterations.
    #
    # @param interval [Number] interval between consecutive iterations in seconds
    # @return [void]
    def every(interval, &block)
      Polyphony.backend_timer_loop(interval, &block)
    end

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
    #   move_on_after(10) {
    #     sleep 60
    #     42
    #   } #=> nil
    #
    #   move_on_after(10, with_value: :oops) {
    #     sleep 60
    #     42
    #   } #=> :oops
    #
    # The timeout period can be reset by passing a block that takes a single
    # argument. The block will be provided with the canceller fiber. To reset
    # the timeout, use `Fiber#reset`, as shown in the following example:
    #
    #   move_on_after(10) do |timeout|
    #     loop do
    #       msg = socket.gets
    #       timeout.reset
    #       handle_msg(msg)
    #     end
    #   end
    #
    # @overload move_on_after(interval) { ... }
    #   @param interval [Number] timout in seconds
    #   @yield [Fiber] timeout fiber
    #   @return [any] block's return value
    # @overload move_on_after(interval, with_value: value) { ... }
    #   @param interval [Number] timout in seconds
    #   @param with_value [any] return value in case of timeout
    #   @yield [Fiber] timeout fiber
    #   @return [any] block's return value
    def move_on_after(interval, with_value: nil, &block)
      if block.arity > 0
        move_on_after_with_optional_reset(interval, with_value, &block)
      else
        Polyphony.backend_timeout(interval, nil, with_value, &block)
      end
    end

    # Returns the first message from the current fiber's mailbox. If the mailbox
    # is empty, blocks until a message is available.
    #
    # @return [any] received message
    def receive
      Fiber.current.receive
    end

    # Returns all messages currently pending on the current fiber's mailbox.
    #
    # @return [Array] array of received messages
    def receive_all_pending
      Fiber.current.receive_all_pending
    end

    # Supervises the current fiber's children. See `Fiber#supervise` for
    # options.
    #
    # @param args [Array] positional parameters
    # @param opts [Hash] named parameters
    # @return [void]
    def supervise(*args, **opts, &block)
      Fiber.current.supervise(*args, **opts, &block)
    end

    # Sleeps for the given duration. If the duration is `nil`, sleeps
    # indefinitely.
    #
    # @param duration [Number, nil] duration
    # @return [void]
    def sleep(duration = nil)
      duration ?
        Polyphony.backend_sleep(duration) : Polyphony.backend_wait_event(true)
    end

    # Starts a throttled loop with the given rate. If `count:` is given, the
    # loop is run for the given number of times. Otherwise, the loop is
    # infinite. The loop rate (times per second) can be given as the rate
    # parameter. The throttling can also be controlled by providing an
    # `interval:` or `rate:` named parameter.
    #
    # @param rate [Number, nil] loop rate (times per second)
    # @option opts [Number] :rate loop rate (times per second)
    # @option opts [Number] :interval loop interval in seconds
    # @option opts [Number] :count number of iterations (nil for infinite)
    # @return [void]
    def throttled_loop(rate = nil, **opts, &block)
      throttler = Polyphony::Throttler.new(rate || opts)
      if opts[:count]
        opts[:count].times { |_i| throttler.(&block) }
      else
        while true
          throttler.(&block)
        end
      end
    rescue LocalJumpError, StopIteration
      # break called or StopIteration raised
    end

    private

    # Helper method for performing a `cancel_after` with optional reset.
    #
    # @param interval [Number] timeout interval in seconds
    # @param exception [Exception, Class, Array<class, message>] exception spec
    # @return [any] block's return value
    def cancel_after_with_optional_reset(interval, exception, &block)
      fiber = Fiber.current
      canceller = spin do
        Polyphony.backend_sleep(interval)
        exception = cancel_exception(exception)
        exception.raising_fiber = Fiber.current
        fiber.cancel(exception)
      end
      block.call(canceller)
    ensure
      canceller.stop
    end

    # Converts the given exception spec to an exception instance.
    #
    # @param exception [Exception, Class, Array<class, message>] exception spec
    # @return [Exception] exception instance
    def cancel_exception(exception)
      case exception
      when Class then exception.new
      when Array then exception[0].new(exception[1])
      else RuntimeError.new(exception)
      end
    end

    # Helper method for performing `#spin_loop` without throttling. Spins up a
    # new fiber in which to run the loop.
    #
    # @param tag [any] new fiber's tag
    # @param caller [Array<String>] caller info
    # @param block [Proc] code to run
    # @return [void]
    def spin_loop_without_throttling(tag, caller, block)
      Fiber.current.spin(tag, caller) do
        block.call while true
      rescue LocalJumpError, StopIteration
        # break called or StopIteration raised
      end
    end

    # Helper method for performing `#move_on_after` with optional reset.
    #
    # @param interval [Number] timeout interval in seconds
    # @param value [any] return value in case of timeout
    # @return [any] return value of given block or timeout value
    def move_on_after_with_optional_reset(interval, value, &block)
      fiber = Fiber.current
      canceller = spin do
        sleep interval
        fiber.move_on(value)
      end
      block.call(canceller)
    rescue Polyphony::MoveOn => e
      e.value
    ensure
      canceller.stop
    end

  end
end
