# frozen_string_literal: true

# Overrides for Process module
module ::Process
  module StatusExtensions
    def coredump?
      @status ? nil : super
    end

    def exited?
      @status ? WIFEXITED(@status[1]) : super
    end

    def exitstatus
      @status ? WEXITSTATUS(@status[1]) : super
    end

    def inspect
      @status ? "#<Process::Status: pid #{@status[0]} exit #{@status[1]}>" : super
    end

    def pid
      @status ? @status[0] : super
    end

    def signaled?
      @status ? WIFSIGNALED(@status[1]) : super
    end

    def stopped?
      @status ? WIFSTOPPED(@status[1]) : super
    end

    def stopsig
      @status ? WIFSTOPPED(@status[1]) && WEXITSTATUS(@status[1]) : super
    end

    def success?
      @status ? @status[1] == 0 : super
    end

    def termsig
      @status ? WIFSIGNALED(@status[1]) && WTERMSIG(@status[1]) : super
    end

    private

    # The following helper methods are translated from the C source:
    # https://github.com/ruby/ruby/blob/v3_2_0/process.c

    def WIFEXITED(w)
      (w & 0xff) == 0
    end

    def WEXITSTATUS(w)
      (w >> 8) & 0xff
    end

    def WIFSIGNALED(w)
      (w & 0x7f) > 0 && ((w & 0x7f) < 0x7f)
    end

    def WIFSTOPPED(w)
      (w & 0xff) == 0x7f
    end

    def WTERMSIG(w)
      w & 0x7f
    end
  end

  class Status
    prepend StatusExtensions

    def self.from_status_array(arr)
      allocate.tap { |s| s.instance_variable_set(:@status, arr) }
    end
  end

  class << self
    # @!visibility private
    alias_method :orig_detach, :detach

    # Detaches the given pid and returns a fiber waiting on it.
    #
    # @param pid [Integer] child pid
    # @return [Fiber] new fiber waiting on pid
    def detach(pid)
      fiber = spin { ::Process::Status.from_status_array(Polyphony.backend_waitpid(pid)) }
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
