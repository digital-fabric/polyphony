# frozen_string_literal: true

require 'modulation/gem'

export_default :Polyphony

require 'fiber'
require_relative './gyro_ext'

Thread.event_selector = Gyro::Selector
Thread.current.setup_fiber_scheduling

import './polyphony/extensions/core'
import './polyphony/extensions/thread'
import './polyphony/extensions/fiber'
import './polyphony/extensions/io'

# Main Polyphony API
module Polyphony
  GlobalAPI = import './polyphony/core/global_api'
  ::Object.include GlobalAPI

  exceptions = import './polyphony/core/exceptions'
  Cancel = exceptions::Cancel
  MoveOn = exceptions::MoveOn

  Net = import './polyphony/net'

  auto_import(
    CancelScope:  './polyphony/core/cancel_scope',
    Channel:      './polyphony/core/channel',
    FS:           './polyphony/fs',
    ResourcePool: './polyphony/core/resource_pool',
    Sync:         './polyphony/core/sync',
    ThreadPool:   './polyphony/core/thread_pool',
    Throttler:    './polyphony/core/throttler',
    Trace:        './polyphony/trace',
    Websocket:    './polyphony/websocket'
  )

  class << self
    def wait_for_signal(sig)
      fiber = Fiber.current
      Gyro.ref
      old_trap = trap(sig) do
        Gyro.unref
        fiber.schedule(sig)
        trap(sig, old_trap)
      end
      suspend
    end

    def fork(&block)
      pid = Kernel.fork do
        Gyro.post_fork
        Fiber.current.setup_main_fiber
        block.()
      end
      pid
    end
  end
end

# install signal handlers

def install_terminating_signal_handler(signal, exception_class)
  trap(signal) do
    exception = exception_class.new
    if Fiber.current.main?
      raise exception
    else
      Thread.current.break_out_of_ev_loop(exception)
    end
  end
end

install_terminating_signal_handler('SIGTERM', SystemExit)
install_terminating_signal_handler('SIGINT', Interrupt)
