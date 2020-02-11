# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

Exception.__disable_sanitized_backtrace__ = true

child_pid = Polyphony.fork do
  at_exit do
    puts "at_exit"
    f = spin { sleep 10 }
    trap('SIGINT') { f.stop }
    f.await
  end
  
  f1 = spin { sleep 100 }
  
  puts "pid: #{Process.pid}"
  
  pid = Process.pid
  
  f1.join
end

sleep 0.1
Process.kill('INT', child_pid)
sleep 0.1
Process.kill('INT', child_pid)
Process.wait(child_pid)
