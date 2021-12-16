# frozen_string_literal: true

# Overrides for Process
module ::Process
  class << self
    alias_method :orig_detach, :detach
    def detach(pid)
      fiber = spin { Polyphony.backend_waitpid(pid) }
      fiber.define_singleton_method(:pid) { pid }
      fiber
    end

    alias_method :orig_daemon, :daemon
    def daemon(*args)
      orig_daemon(*args)
      Polyphony.original_pid = Process.pid
    end
  end
end
