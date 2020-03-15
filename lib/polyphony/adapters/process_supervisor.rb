# frozen_string_literal: true

export :supervise

def supervise(cmd = nil, _opts = {}, &block)
  spin { watch_process(cmd, &block) }
  Kernel.supervise(on_error: :restart)
end

class ProcessExit < ::RuntimeError; end

def watch_process(cmd = nil, &block)
  terminated = nil
  pid = cmd ? Kernel.spawn(cmd) : Polyphony.fork(&block)
  watcher = Gyro::Child.new(pid)
  watcher.await
  terminated = true
  raise ProcessExit
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
  Process.kill(sig, pid)
  Gyro::Child.new(pid).await
rescue SystemCallError
  # ignore
  puts 'SystemCallError in kill_and_await'
end
