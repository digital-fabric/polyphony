# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

Exception.__disable_sanitized_backtrace__ = true

puts "Parent pid: #{Process.pid}"

def start_worker
  Polyphony.fork do
    p :sleep
    sleep 5
    p :done_sleeping
  ensure
    p :start_worker_fork_ensure
  end
end

f = spin do
  Polyphony::ProcessSupervisor.supervise do
    spin do
      spin do
        p :sleep
        sleep 5
        p :done_sleeping
      end.await
    end.await
  ensure
    p :start_worker_fork_ensure
  end
  # spin do
  #   pid = start_worker
  #   p [:before_child_await, pid]
  #   Gyro::Child.new(pid).await
  #   p :after_child_await
  # ensure
  #   puts "child done"
  # end
  # supervise
# ensure
#   puts "kill child"
#   Process.kill('TERM', pid) rescue nil
end

sleep 1
puts "terminate worker"
f.terminate
f.await