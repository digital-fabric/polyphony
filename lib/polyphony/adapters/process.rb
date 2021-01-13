# frozen_string_literal: true

module Polyphony
  # Process patches
  module Process
    class << self
      def watch(cmd = nil, &block)
        terminated = nil
        pid = cmd ? Kernel.spawn(cmd) : Polyphony.fork(&block)
        Thread.current.backend.waitpid(pid)
        terminated = true
      ensure
        kill_process(pid) unless terminated || pid.nil?
      end

      def kill_process(pid)
        cancel_after(5) do
          kill_and_await('TERM', pid)
        end
      rescue Polyphony::Cancel
        kill_and_await(-9, pid)
      end

      def kill_and_await(sig, pid)
        ::Process.kill(sig, pid)
        Thread.current.backend.waitpid(pid)
      rescue Errno::ERSCH
        # ignore
      end
    end
  end
end
