# frozen_string_literal: true

export_default :Channel

Exceptions = import('./exceptions')

class Channel
  def initialize
    @payload_queue = []
    @waiting_queue = []
  end

  def close
    stop = Exceptions::Stopped.new
    @waiting_queue.slice(0..-1).each { |f| f.resume(stop) }
  end

  def <<(o)
    if @waiting_queue.empty?
      @payload_queue << o
    else
      @waiting_queue.shift&.resume(o)
    end
  end

  def receive
    proc do
      if @payload_queue.empty?
        @waiting_queue << Fiber.current
      else
        payload = @payload_queue.shift
        fiber = Fiber.current
        EV.next_tick { fiber.resume(payload) }
      end
      suspend
    end
  end
end