# frozen_string_literal: true

export_default :Channel

class Channel
  def initialize
    @queue = []
    @async_watcher = EV::Async.new
  end

  def close
    @async_watcher.stop
    if @waiting_fiber
      @waiting_fiber.resume Stopped.new
    end
  end

  def <<(o)
    @queue << o
    @async_watcher.signal!
  end

  def receive
    proc do
      @waiting_fiber = Fiber.current
      @async_watcher.await
      @waiting_fiber = nil
      o = @queue.shift
      @async_watcher.signal! unless @queue.empty?
      o
    end
  end
end