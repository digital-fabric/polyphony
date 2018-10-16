# frozen_string_literal: true

export :Mutex

class Mutex
  def initialize
    @waiting = []
  end

  def acquire(&block)
    fiber = Fiber.current
    @waiting << fiber
    Fiber.yield if @waiting.size > 1
    block.call
  ensure
    @waiting.shift if @waiting[0] == fiber
    dequeue unless @waiting.empty?
  end

  def dequeue
    EV.next_tick { @waiting[0]&.resume }
  end
end

