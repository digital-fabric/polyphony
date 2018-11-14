# frozen_string_literal: true

Async       = import('./async')
CancelScope = import('./cancel_scope')
Coroutine   = import('./coroutine')
Exceptions  = import('./exceptions')
Supervisor  = import('./supervisor')

# Kernel extensions (methods available to all objects)
module ::Kernel
  def after(duration, &block)
    EV::Timer.new(freq, 0).start(&block)
  end

  def async(sym = nil, &block)
    if sym
      Async.async_decorate(is_a?(Class) ? self : singleton_class, sym)
    else
      Coroutine.new(&block)
    end
  end

  def await(proc = nil, &block)
    return if Fiber.current.cancelled?

    if proc && block
      proc.(&block)
    else
      (block || proc).()
    end
  end

  def cancel_after(duration, &block)
    CancelScope.new(timeout: duration, mode: :cancel).(&block)
  end

  def every(freq, &block)
    EV::Timer.new(freq, freq).start(&block)
  end

  def move_on_after(duration, &block)
    CancelScope.new(timeout: duration).(&block)
  end

  def pulse(freq)
    fiber = Fiber.current
    timer = EV::Timer.new(freq, freq)
    timer.start { fiber.resume freq }
    proc do
      suspend
    rescue Exception => e
      timer.stop
      raise e
    end
  end

  alias_method :sync_sleep, :sleep
  def sleep(duration)
    proc do
      timer = EV::Timer.new(duration, 0)
      timer.await
    ensure
      timer.stop
    end
  end

  def snooze
    fiber = Fiber.current
    EV.next_tick { fiber.resume }
    Fiber.yield
  end

  def spawn(proc = nil, &block)
    if proc.is_a?(Coroutine)
      proc.run
    else
      Coroutine.new(&(block || proc)).run
    end
  end

  def supervise(&block)
    Supervisor.new.(&block)
  end

  def suspend
    result = Fiber.yield
    result.is_a?(Exception) ? raise(result) : result
  end

  def timeout(duration, opts = {}, &block)
    CancelScope.new(opts.merge(timeout: duration)).(&block)
  end
end

class ::Fiber
  attr_writer :cancelled

  def cancelled?
    @cancelled
  end
end