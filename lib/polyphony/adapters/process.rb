# frozen_string_literal: true

module Polyphony
  # Process extensions
  module Process
    class << self

      # Watches a forked or spawned process, waiting for it to terminate. If
      # `cmd` is given it is spawned, otherwise the process is forked with the
      # given block.
      # 
      # If the operation is interrupted for any reason, the spawned or forked
      # process is killed.
      #
      # @param cmd [String, nil] command to spawn
      # @param &block [Proc] block to fork
      # @return [void]
      def watch(cmd = nil, &block)
        terminated = nil
        pid = cmd ? Kernel.spawn(cmd) : Polyphony.fork(&block)
        Polyphony.backend_waitpid(pid)
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

      private

      def kill_and_await(sig, pid)
        ::Process.kill(sig, pid)
        Polyphony.backend_waitpid(pid)
      rescue Errno::ESRCH
        # process doesn't exist
      end
    end
  end
end
