# frozen_string_literal: true

require 'fiber'

CancelScope = import('../core/cancel_scope')
Coprocess   = import('../core/coprocess')
Exceptions  = import('../core/exceptions')
Supervisor  = import('../core/supervisor')
Throttler   = import('../core/throttler')

# Fiber extensions
class ::Fiber
  attr_writer :cancelled
  attr_accessor :next_job, :coprocess

  def cancelled?
    @cancelled
  end

  def schedule(value = nil)
    EV.schedule_fiber(self, value)
  end

  # Associate a (pseudo-)coprocess with the main fiber
  current.coprocess = Coprocess.new(current)
end

class ::Exception
  SANITIZE_RE = /lib\/polyphony/.freeze
  SANITIZE_PROC = proc  { |l| l !~ SANITIZE_RE }

  def cleanup_backtrace(caller = nil)
    combined = caller ? backtrace + caller : backtrace
    set_backtrace(combined.select(&SANITIZE_PROC))
  end
end

# Kernel extensions (methods available to all objects)
module ::Kernel
  def after(duration, &block)
    EV::Timer.new(freq, 0).start(&block)
  end

  def async(sym = nil, &block)
    if sym
      async_decorate(is_a?(Class) ? self : singleton_class, sym)
    else
      Coprocess.new(&block)
    end
  end

  # Converts a regular method into an async method, i.e. a method that returns a
  # proc that eventually executes the original code.
  # @param receiver [Object] object receiving the method call
  # @param sym [Symbol] method name
  # @return [void]
  def async_decorate(receiver, sym)
    sync_sym = :"sync_#{sym}"
    receiver.alias_method(sync_sym, sym)
    receiver.define_method(sym) do |*args, &block|
      Coprocess.new { send(sync_sym, *args, &block) }
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

  class Pulser
    def initialize(freq)
      fiber = Fiber.current
      @timer = EV::Timer.new(freq, freq)
      @timer.start { fiber.transfer freq }
    end

    def await
      suspend
    rescue Exception => e
      @timer.stop
      raise e
    end

    def stop
      @timer.stop
    end
  end

  def pulse(freq)
    Pulser.new(freq)
  end

  def receive
    Fiber.current.coprocess.receive
  end

  alias_method :sync_sleep, :sleep
  def sleep(duration)
    timer = EV::Timer.new(duration, 0)
    timer.await
  ensure
    timer.stop
  end

  def spawn(proc = nil, &block)
    if proc.is_a?(Coprocess)
      proc.run
    else
      Coprocess.new(&(block || proc)).run
    end
  end

  def supervise(&block)
    Supervisor.new.await(&block)
  end

  def throttled_loop(rate, &block)
    throttler = Throttler.new(rate)
    loop do
      throttler.(&block)
    end
  end

  def throttle(rate)
    Throttler.new(rate)
  end

  def timeout(duration, opts = {}, &block)
    CancelScope.new(**opts, timeout: duration).(&block)
  end
end

