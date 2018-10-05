# frozen_string_literal: true

export_default :Core

require_relative '../ev_ext'

# Core module, containing async and reactor methods
module Core
  extend import('./core/async')

  def self.timeout(t, &cb)
    EV::Timer.new(t, 0, &cb)
  end

  def self.interval(t, &cb)
    EV::Timer.new(t, t, &cb)
  end

  def self.next_tick(&cb)
    EV::Timer.new(0, 0, &cb)
  end

  def self.trap(sig, &cb)
    sig = Signal.list[sig.to_s.upcase] if sig.is_a?(Symbol)
    EV::Signal.new(sig, &cb)
  end
end

def auto_run
  raise $! if $!
  Core.trap(:int) { puts; EV.break }
  EV.unref # undo ref count increment caused by signal trap
  EV.run
rescue Exception => e
  puts "Exception: #{e}"
  puts e.backtrace.join("\n")
end

at_exit { auto_run }