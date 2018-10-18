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
    @sigint_watcher = EV::Signal.new(sig, &callback)
  end

  def self.at_exit(&block)
    @exit_tasks ||= []
    @exit_tasks << block
  end

  def self.run_exit_procs
    return unless @exit_tasks

    @exit_tasks.each { |t| t.call rescue nil }
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

at_exit do
  auto_run
  Core.run_exit_procs
end
