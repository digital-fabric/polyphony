# frozen_string_literal: true

export_default :API

import '../extensions/core'

Coprocess   = import '../core/coprocess'
Exceptions  = import '../core/exceptions'
Supervisor  = import '../core/supervisor'
Throttler   = import '../core/throttler'

# Global API methods to be included in ::Object
module API
  def after(interval, &block)
    spin do
      sleep interval
      block.()
    end
  end

  def cancel_after(interval, &block)
    fiber = ::Fiber.current
    canceller = spin do
      sleep interval
      fiber.schedule Exceptions::Cancel.new
    end
    block.call
  ensure
    canceller.stop
  end

  def defer(&block)
    ::Fiber.new(&block).schedule
  end

  def spin(&block)
    Coprocess.new(&block).run
  end

  def spin_loop(&block)
    spin { loop(&block) }
  end

  def every(interval)
    timer = Gyro::Timer.new(interval, interval)
    loop do
      timer.await
      yield
    end
  end

  def move_on_after(interval, with_value: nil, &block)
    fiber = ::Fiber.current
    canceller = spin do
      sleep interval
      fiber.schedule Exceptions::MoveOn.new(nil, with_value)
    end
    block.call
  rescue Exceptions::MoveOn => e
    e.value
  ensure
    canceller.stop
  end

  def receive
    Fiber.current.coprocess.receive
  end

  def sleep(duration)
    timer = Gyro::Timer.new(duration, 0)
    timer.await
  end

  def supervise(&block)
    Supervisor.new.await(&block)
  end

  def throttled_loop(rate, count: nil, &block)
    throttler = Throttler.new(rate)
    if count
      count.times { throttler.(&block) }
    else
      loop { throttler.(&block) }
    end
  end
end
