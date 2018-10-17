# frozen_string_literal: true

export :Mutex

# Implements mutex lock for synchronizing async operations
class Mutex
  def initialize
    @waiting = []
  end

  def synchronize
    proc do |&block|
      fiber = Fiber.current
      @waiting << fiber
      Fiber.yield_and_raise_error if @waiting.size > 1
      block.()
    ensure
      @waiting.delete(fiber)
      EV.next_tick { @waiting[0]&.resume } unless @waiting.empty?
    end
  end
end
