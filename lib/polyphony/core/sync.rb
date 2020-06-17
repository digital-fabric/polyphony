# frozen_string_literal: true

module Polyphony
  # Implements mutex lock for synchronizing access to a shared resource
  class Mutex
    def initialize
      @waiting_fibers = Polyphony::Queue.new
    end

    def synchronize
      fiber = Fiber.current
      @waiting_fibers << fiber
      suspend if @waiting_fibers.size > 1
      yield
    ensure
      @waiting_fibers.delete(fiber)
      @waiting_fibers.first&.schedule
      snooze
    end
  end
end
