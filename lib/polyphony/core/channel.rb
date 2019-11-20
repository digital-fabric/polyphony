# frozen_string_literal: true

export_default :Channel

Exceptions = import('./exceptions')

# Implements a unidirectional communication channel along the lines of Go
# (buffered) channels.
class Channel
  def initialize
    @payload_queue = []
    @waiting_queue = []
  end

  def close
    stop = Exceptions::MoveOn.new
    @waiting_queue.slice(0..-1).each { |f| f.schedule(stop) }
  end

  def <<(value)
    if @waiting_queue.empty?
      @payload_queue << value
    else
      @waiting_queue.shift&.schedule(value)
    end
    snooze
  end

  def receive
    Gyro.ref
    if @payload_queue.empty?
      @waiting_queue << Fiber.current
      suspend
    else
      receive_from_queue
    end
  ensure
    Gyro.unref
  end

  def receive_from_queue
    payload = @payload_queue.shift
    snooze
    payload
  end
end
