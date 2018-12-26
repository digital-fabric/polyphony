# frozen_string_literal: true

export :Mutex

# Implements mutex lock for synchronizing async operations
class Mutex
  def initialize
    @waiting = []
  end

  def synchronize
    fiber = Fiber.current
    @waiting << fiber
    suspend if @waiting.size > 1
    yield
  ensure
    @waiting.delete(fiber)
    EV.next_tick { @waiting[0]&.transfer } unless @waiting.empty?
  end
end
