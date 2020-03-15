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
  Cancel    = exceptions::Cancel
  MoveOn    = exceptions::MoveOn
  Restart   = exceptions::Restart
  Terminate = exceptions::Terminate

  Net = import './polyphony/net'

  auto_import(
    Channel:            './polyphony/core/channel',
    FS:                 './polyphony/adapters/fs',
    ProcessSupervisor:  './polyphony/adapters/process_supervisor',
    ResourcePool:       './polyphony/core/resource_pool',
    Sync:               './polyphony/core/sync',
    ThreadPool:         './polyphony/core/thread_pool',
    Throttler:          './polyphony/core/throttler',
    Trace:              './polyphony/adapters/trace'
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
      Kernel.fork do
        Fiber.new do
          trap('SIGTERM', 'DEFAULT')
          trap('SIGINT', 'DEFAULT')

          Thread.current.post_fork
          Thread.current.setup
          Fiber.current.setup_main_fiber

          install_terminating_signal_handlers

          block.()
        rescue ::SystemExit
          Fiber.current.shutdown_all_children
          exit
        rescue Exception => e
          e.full_message
          exit!
        ensure
          Fiber.current.shutdown_all_children
          # Since fork could be called from any fiber, we explicitly call exit
          # here. Otherwise, the fiber might want to pass execution to another
          # fiber that previously transferred execution to the forking fiber, but
          # doesn't exist anymore... The call to exit will invoke the at_exit
          # handler we use to terminate the (forked) main fiber's child fibers.
          exit
        end.transfer
      end
    end
  
    def install_terminating_signal_handler(signal, exception_class)
      trap(signal) do
        exception = exception_class.new
        Thread.current.break_out_of_ev_loop(Thread.main.main_fiber, exception)
      end
    end

    def install_terminating_signal_handlers
      install_terminating_signal_handler('SIGTERM', ::SystemExit)
      install_terminating_signal_handler('SIGINT', ::Interrupt)
    end
  end

end

Polyphony.install_terminating_signal_handlers

