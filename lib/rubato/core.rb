# frozen_string_literal: true

export_default :Core

require 'fiber'
require_relative '../ev_ext'

import('./extensions/kernel')
FiberPool = import('./core/fiber_pool')

# Core module, containing async and reactor methods
module Core
  def self.debug=(v); @debug = v; end
  def self.debug; @debug; end

  def self.trap(sig, ref = false, &callback)
    sig = Signal.list[sig.to_s.upcase] if sig.is_a?(Symbol)
    EV::Signal.new(sig, &callback)
    EV.unref unless ref
  end

  def self.fork(&block)
    EV.break
    pid = Kernel.fork do
      FiberPool.reset!
      EV.post_fork
      Fiber.current.coroutine = Coroutine.new(Fiber.current)

      block.()

      # We cannot simply depend on the at_exit block (see below) to yield to the
      # reactor fiber. Doing that will raise a FiberError complaining: "fiber
      # called across stack rewinding barrier". Apparently this is a bug in
      # Ruby, so the workaround is to yield just before exiting.
      suspend
    end
    EV.restart
    pid
  end
end

at_exit do
  # in most cases, by the main fiber is done there are still pending or other
  # or asynchronous operations going on. If the reactor loop is not done, we
  # suspend the root fiber until it is done
  suspend if $__reactor_fiber__.alive?
end
