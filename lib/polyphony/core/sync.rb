# frozen_string_literal: true

export :Mutex

# Implements mutex lock for synchronizing access to a shared resource
class Mutex
  def initialize
    @waiting_fibers = []
  end

  def synchronize(&block)
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
