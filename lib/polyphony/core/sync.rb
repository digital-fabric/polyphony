# frozen_string_literal: true

module Polyphony
  # Implements mutex lock for synchronizing access to a shared resource
  class Mutex
    def initialize
      @store = Queue.new
      @store << :token
    end

    def synchronize(&block)
      return yield if @holding_fiber == Fiber.current

      synchronize_not_holding(&block)
    end

    def synchronize_not_holding
      @token = @store.shift
      begin
        @holding_fiber = Fiber.current
        yield
      ensure
        @holding_fiber = nil
        @store << @token if @token
      end
    end

    def conditional_release
      @store << @token
      @token = nil
      @holding_fiber = nil
    end

    def conditional_reacquire
      @token = @store.shift
      @holding_fiber = Fiber.current
    end

    def owned?
      @holding_fiber == Fiber.current
    end

    def locked?
      @holding_fiber
    end
  end

  # Implements a fiber-aware ConditionVariable
  class ConditionVariable
    def initialize
      @queue = Polyphony::Queue.new
    end

    def wait(mutex, _timeout = nil)
      mutex.conditional_release
      @queue << Fiber.current
      Polyphony.backend_wait_event(true)
      mutex.conditional_reacquire
    end

    def signal
      fiber = @queue.shift
      fiber.schedule
    end

    def broadcast
      while (fiber = @queue.shift)
        fiber.schedule
      end
    end
  end
end
