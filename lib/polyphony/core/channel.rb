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
    @waiting_queue.slice(0..-1).each { |f| f.schedule(stop) }
  end

  def <<(o)
    if @waiting_queue.empty?
      @payload_queue << o
    else
      @waiting_queue.shift&.schedule(o)
    end
    snooze
  end

  def receive
    Gyro.ref
    if @payload_queue.empty?
      @waiting_queue << Fiber.current
      suspend
    else
      payload = @payload_queue.shift
      snooze
      payload
    end
  ensure
    Gyro.unref
  end
end