# frozen_string_literal: true

require 'modulation/gem'

export_default :Polyphony

require 'fiber'
require_relative './gyro_ext'

import './polyphony/extensions/core'
import './polyphony/extensions/io'

# Main Polyphony API
module Polyphony
  GlobalAPI = import './polyphony/core/global_api'
  ::Object.include GlobalAPI

  exceptions = import './polyphony/core/exceptions'
  Cancel        = exceptions::Cancel
  MoveOn        = exceptions::MoveOn

  Coprocess = import './polyphony/core/coprocess'
  Net       = import './polyphony/net'

  auto_import(
    CancelScope:  './polyphony/core/cancel_scope',
    Channel:      './polyphony/core/channel',
    FS:           './polyphony/fs',
    ResourcePool: './polyphony/core/resource_pool',
    Supervisor:   './polyphony/core/supervisor',
    Sync:         './polyphony/core/sync',
    Thread:       './polyphony/core/thread',
    ThreadPool:   './polyphony/core/thread_pool',
    Websocket:    './polyphony/websocket'
  )

  class << self
    # def trap(sig, ref = false, &callback)
    #   sig = Signal.list[sig.to_s.upcase] if sig.is_a?(Symbol)
    #   puts "sig = #{sig.inspect}"
    #   watcher = Gyro::Signal.new(sig, &callback)
    #   # Gyro.unref unless ref
    #   watcher
    # end

    def wait_for_signal(sig)
      fiber = Fiber.current
      Gyro.ref
      trap(sig) do
        trap(sig, :DEFAULT)
        Gyro.unref
        fiber.transfer(sig)
      end
      suspend
    end

    def fork(&block)
      Gyro.break!
      pid = Kernel.fork do
        setup_forked_process
        block.()
      end
      Gyro.reset!
      pid
    end

    def reset!
      # Fiber.root.scheduled_value = nil
      Gyro.reset!
      Coprocess.map.clear
    end

    private

    def setup_forked_process
      Coprocess.map.delete Fiber.root
      Gyro.post_fork
      Fiber.set_root_fiber
    end
  end
end
