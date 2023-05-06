# frozen_string_literal: true

# Overrides for Process module
module ::Process
  class << self
    # @!visibility private
    alias_method :orig_detach, :detach

    # Detaches the given pid and returns a fiber waiting on it.
    #
    # @param pid [Integer] child pid
    # @return [Fiber] new fiber waiting on pid
    def detach(pid)
      fiber = spin { Polyphony.backend_waitpid(pid) }
      fiber.define_singleton_method(:pid) { pid }
      fiber
    end

    # @!visibility private
    alias_method :orig_daemon, :daemon

    # Starts a daemon with the given arguments.
    #
    # @param args [any] arguments to pass to daemon
    # @return [Integer] daemon pid
    def daemon(*args)
      orig_daemon(*args)
      Polyphony.original_pid = Process.pid
    end
  end
end
