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
        token = @store.shift
        @holding_fiber = Fiber.current
        yield
      ensure
        @holding_fiber = nil
        @store << token if token
      end
    end
  end
end
