# frozen_string_literal: true

export_default :Channel

Exceptions = import('./exceptions')

class Channel
  def initialize
    @payload_queue = []
    @waiting_queue = []
  end

  def close
    stop = Exceptions::MoveOn.new
    @waiting_queue.slice(0..-1).each { |f| f.transfer(stop) }
  end

  def <<(o)
    if @waiting_queue.empty?
      @payload_queue << o
    else
      @waiting_queue.shift&.transfer(o)
    end
  end

  def receive
    if @payload_queue.empty?
      @waiting_queue << Fiber.current
    else
      payload = @payload_queue.shift
      fiber = Fiber.current
      EV.next_tick { fiber.transfer(payload) }
    end
    suspend
  end
end