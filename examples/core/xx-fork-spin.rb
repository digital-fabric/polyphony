# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

Exception.__disable_sanitized_backtrace__ = true

puts "Parent pid: #{Process.pid}"

i, o = IO.pipe

pid = Polyphony.fork do
  puts "Child pid: #{Process.pid}"
  i.close
  spin do
    spin do
      p :sleep
      sleep 1
    rescue ::Interrupt => e
      p 1
      # the signal should be raised only in the main fiber
      o.puts "1-interrupt"
    end.await
  rescue Polyphony::Terminate
    puts "terminate!"
  end.await
rescue ::Interrupt => e
  p 2
  o.puts "3-interrupt"
ensure
  p 3
  o.close
end
sleep 0.2
o.close
watcher = Gyro::Child.new(pid)
Process.kill('INT', pid)
watcher.await
buffer = i.read

puts '*' * 40
p buffer
