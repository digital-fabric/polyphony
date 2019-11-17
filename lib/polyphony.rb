# frozen_string_literal: true

require 'modulation/gem'

export_default :Polyphony

require 'fiber'
require_relative './gyro_ext'
import('./polyphony/extensions/kernel')
import('./polyphony/extensions/io')

module Polyphony
  exceptions = import('./polyphony/core/exceptions')
  Cancel        = exceptions::Cancel
  MoveOn        = exceptions::MoveOn

  Coprocess = import('./polyphony/core/coprocess')
  FiberPool = import('./polyphony/core/fiber_pool')
  Net       = import('./polyphony/net')


  def self.trap(sig, ref = false, &callback)
    sig = Signal.list[sig.to_s.upcase] if sig.is_a?(Symbol)
    watcher = Gyro::Signal.new(sig, &callback)
    Gyro.unref unless ref
    watcher
  end
  
  def self.fork(&block)
    Gyro.break
    pid = Kernel.fork do
      FiberPool.reset!
      Gyro.post_fork
      Fiber.set_main_fiber
      Fiber.current.coprocess = Coprocess.new(Fiber.current)
  
      block.()
  
      # We cannot simply depend on the at_exit block (see below) to yield to the
      # reactor fiber. Doing that will raise a FiberError complaining: "fiber
      # called across stack rewinding barrier". Apparently this is a bug in
      # Ruby, so the workaround is to yield just before exiting.
      suspend
    end
    Gyro.restart
    pid
  end
  
  def self.debug
    @debug
  end
  
  def self.debug=(value)
    @debug = value
  end
  
  def self.reset!
    # FiberPool.reset!
    Fiber.main.scheduled_value = nil
    Gyro.restart
  end
  
  auto_import(
    CancelScope:  './polyphony/core/cancel_scope',
    Channel:      './polyphony/core/channel',
    # Coprocess:    './polyphony/core/coprocess',
    FS:           './polyphony/fs',
    # Net:          './polyphony/net',
    ResourcePool: './polyphony/core/resource_pool',
    Supervisor:   './polyphony/core/supervisor',
    Sync:         './polyphony/core/sync',
    Thread:       './polyphony/core/thread',
    ThreadPool:   './polyphony/core/thread_pool',
    Websocket:    './polyphony/websocket'
  )
end
