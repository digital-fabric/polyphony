# frozen_string_literal: true

module Polyphony
  # Implements mutex lock for synchronizing access to a shared resource
  class Mutex
    def initialize
      @store = Queue.new
      @store << :token
    end

    def synchronize
      return yield if @holding_fiber == Fiber.current

      begin
        @token = @store.shift
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
  end

  class ConditionVariable
    def initialize
      @queue = Polyphony::Queue.new
    end

    def wait(mutex, timeout = nil)
      mutex.conditional_release
      @queue << Fiber.current
      Thread.current.backend.wait_event(true)
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
