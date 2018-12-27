# frozen_string_literal: true

export_default :Core

require 'fiber'
require_relative '../ev_ext'

import('./extensions/kernel')

FiberPool = import('./core/fiber_pool')

# Core module, containing async and reactor methods
module Core
  def self.trap(sig, ref = false, &callback)
    sig = Signal.list[sig.to_s.upcase] if sig.is_a?(Symbol)
    EV::Signal.new(sig, &callback)
    EV.unref unless ref
  end

  def self.fork(&block)
    Kernel.fork do
      FiberPool.reset!
      EV.post_fork

      block.()
      run
    end
  end
end

at_exit do
  # in most cases, by the main fiber is done there are still pending or other
  # or asynchronous operations going on. If the reactor loop is not done, we
  # suspend the root fiber until it is done
  suspend if EV.reactor_fiber.alive?
end
