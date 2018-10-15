# frozen_string_literal: true

export_default :Core

require 'fiber'
require_relative '../ev_ext'

Async       = import('./core/async')
CancelScope = import('./core/cancel_scope')
Ext         = import('./core/ext')
FiberPool   = import('./core/fiber_pool')
Nexus       = import('./core/nexus')

module ::Kernel
  @@next_tick_ops = []
  @@next_tick_timer ||= EV::Timer.new(0, 0) { __run_next_tick_ops }
  @@next_tick_timer.stop

  def next_tick(&block)
    @@next_tick_timer.start
    @@next_tick_ops << block
  end

  private def __run_next_tick_ops
    ops = @@next_tick_ops
    @@next_tick_ops = []
    ops.each(&:call)
    @@next_tick_timer.stop if @@next_tick_ops.empty?
  end

  def async(sym = nil, &block)
    if sym
      Async.async_decorate(is_a?(Class) ? self : singleton_class, sym)
    else
      Async.async_task(&block)
    end
  end

  def async!(&block)
    next_tick do
      if block.async
        block.call
      else
        FiberPool.spawn(&block)
      end
    end
  end

  def await(task, &block)
    return nil if Fiber.current.cancelled

    if task && block
      task.call(&block)
    else
      (task || block).call
    end
  rescue Exception => e
    raise e
  end

  def cancel_after(timeout, &block)
    c = CancelScope.new(timeout: timeout)
    c.run(&block)
  end

  def nexus(tasks = nil, &block)
    Nexus.new(tasks, &block).to_proc
  end

  def move_on_after(timeout, &block)
    c = CancelScope.new(timeout: timeout, mode: :move_on)
    c.run(&block)
  end
end

# Core module, containing async and reactor methods
module Core
  def self.sleep(duration)
    proc do
      begin
        fiber = Fiber.current
        timer = EV::Timer.new(duration, 0) { fiber.resume duration }
        Fiber.yield_and_raise_error
      ensure
        timer&.stop
      end
    end
  end

  def self.pulse(freq, &block)
    fiber = Fiber.current
    timer = EV::Timer.new(freq, freq) { fiber.resume freq }
    proc do
      begin
        Fiber.yield_and_raise_error
        # Exception === result ? raise(result) : result
      rescue Exception => e
        timer.stop
        raise e
      end
    end
    # Task.new(start: true) do |t|
    #   timer = EV::Timer.new(freq, freq) { t.resolve(freq) }
    #   t.on_cancel { timer.stop }
    # end
  end

  def self.trap(sig, &cb)
    sig = Signal.list[sig.to_s.upcase] if sig.is_a?(Symbol)
    EV::Signal.new(sig, &cb)
  end
end

def auto_run
  return if @auto_ran
  @auto_ran = true
  
  return if $!
  Core.trap(:int) { puts; EV.break }
  EV.unref # undo ref count increment caused by signal trap
  EV.run
end

at_exit { auto_run }