# frozen_string_literal: true

require 'fiber'
require_relative './polyphony_ext'

require_relative './polyphony/extensions/core'
require_relative './polyphony/extensions/thread'
require_relative './polyphony/extensions/fiber'
require_relative './polyphony/extensions/io'

Thread.current.setup_fiber_scheduling
Thread.current.backend = Polyphony::Backend.new

require_relative './polyphony/core/global_api'
require_relative './polyphony/core/resource_pool'
require_relative './polyphony/core/sync'
require_relative './polyphony/core/timer'
require_relative './polyphony/net'
require_relative './polyphony/adapters/process'

# Polyphony API
module Polyphony
  class << self
    def fork(&block)
      Kernel.fork do
        # A race condition can arise if a TERM or INT signal is received before
        # the forked process has finished initializing. To prevent this we restore
        # the default signal handlers, and then reinstall the custom Polyphony
        # handlers just before running the given block.
        trap('SIGTERM', 'DEFAULT')
        trap('SIGINT', 'DEFAULT')

        # Since the fiber doing the fork will become the main fiber of the
        # forked process, we leave it behind by transferring to a new fiber
        # created in the context of the forked process, which rescues *all*
        # exceptions, including Interrupt and SystemExit.
        spin_forked_block(&block).transfer
      end
    end

    def spin_forked_block(&block)
      Fiber.new do
        run_forked_block(&block)
      rescue SystemExit
        # fall through to ensure
      rescue Exception => e
        STDERR << e.full_message
        exit!
      ensure
        exit_forked_process
      end
    end

    def run_forked_block(&block)
      Thread.current.setup
      Fiber.current.setup_main_fiber
      Thread.current.backend.post_fork

      install_terminating_signal_handlers

      block.()
    end

    def exit_forked_process
      terminate_threads
      Fiber.current.shutdown_all_children

      # Since fork could be called from any fiber, we explicitly call exit here.
      # Otherwise, the fiber might want to pass execution to another fiber that
      # previously transferred execution to the forking fiber, but doesn't exist
      # anymore...
      exit
    end

    def watch_process(cmd = nil, &block)
      Polyphony::Process.watch(cmd, &block)
    end

    def install_terminating_signal_handlers
      trap('SIGTERM') { raise SystemExit }
      orig_trap('SIGINT') do
        orig_trap('SIGINT') { exit! }
        Fiber.schedule_priority_oob_fiber { raise Interrupt }
      end
    end

    def terminate_threads
      threads = Thread.list - [Thread.current]
      return if threads.empty?

      threads.each(&:kill)
      threads.each(&:join)
    end

    attr_accessor :original_pid

    def install_at_exit_handler
      @original_pid = ::Process.pid

      # This at_exit handler is needed only when the original process exits. Due to
      # the behaviour of fibers on fork (and especially on exit from forked
      # processes,) we use a separate mechanism to terminate fibers in forked
      # processes (see Polyphony.fork).
      at_exit do
        next unless @original_pid == ::Process.pid

        Polyphony.terminate_threads
        Fiber.current.shutdown_all_children
      end
    end
  end

  # replace core Queue class with our own
  verbose = $VERBOSE
  $VERBOSE = nil
  Object.const_set(:Queue, Polyphony::Queue)
  Object.const_set(:Mutex, Polyphony::Mutex)
  Object.const_set(:ConditionVariable, Polyphony::ConditionVariable)
  $VERBOSE = verbose
end

Polyphony.install_terminating_signal_handlers
Polyphony.install_at_exit_handler
