# frozen_string_literal: true

export_default :Core

require 'fiber'
require_relative '../ev_ext'

Ext = import('./core/ext')

# Core module, containing async and reactor methods
module Core
  def self.sleep(duration)
    proc do
      fiber = Fiber.current
      timer = EV::Timer.new(duration, 0) { fiber.resume duration }
      suspend
    ensure
      timer&.stop
    end
  end

  def self.pulse(freq)
    fiber = Fiber.current
    timer = EV::Timer.new(freq, freq) { fiber.resume freq }
    proc do
      suspend
    rescue Exception => e
      timer.stop
      raise e
    end
  end

  def self.trap(sig, &callback)
    sig = Signal.list[sig.to_s.upcase] if sig.is_a?(Symbol)
    EV::Signal.new(sig, &callback)
  end
end

def auto_run
  return if @auto_ran
  @auto_ran = true

  return if $!
  Core.trap(:int) do
    puts
    EV.break
  end
  EV.unref # undo ref count increment caused by signal trap
  EV.run
end

at_exit { auto_run }
