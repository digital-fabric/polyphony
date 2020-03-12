# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

Exception.__disable_sanitized_backtrace__ = true

def supervise_process(cmd = nil, &block)
  spin { watch_process(cmd, &block) }
  supervise(on_error: :restart)
end

class ProcessExit < ::RuntimeError; end

def watch_process(cmd = nil, &block)
  puts "watch_process in #{Fiber.current}"
  terminated = nil
  pid = cmd ? Kernel.spawn(cmd) : Polyphony.fork(&block)
  puts "pid: #{pid}"
  watcher = Gyro::Child.new(pid)
  status = watcher.await
  puts "exited with status #{status}"
  terminated = true
  raise ProcessExit
ensure
  kill_process(pid) unless terminated
end

def kill_process(pid)
  cancel_after(3) do
    puts "send TERM to #{pid}"
    kill_and_await('TERM', pid)
    puts "done waiting for #{pid}"
  end
rescue Polyphony::Cancel
  puts "kill #{pid}"
  kill_and_await(-9, pid)
  puts "done waiting for #{pid}"
end

def kill_and_await(sig, pid)
  Process.kill(sig, pid)
  Gyro::Child.new(pid).await
rescue SystemCallError
  # ignore
end

begin
  spin do
    puts "supervisor #{Fiber.current}"
    # supervise_process('ruby examples/core/forever_sleep.rb')
    supervise_process do
      trap('INT') {}
      trap('TERM') {}
      puts "go to sleep"
      sleep 2
    ensure
      puts "done sleeping"
    end
  end.await
rescue ::Interrupt
  # do nothing
end