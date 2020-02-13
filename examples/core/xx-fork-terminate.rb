# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

Exception.__disable_sanitized_backtrace__ = true

pid = Polyphony.fork do
  f = spin do
    p 1
    sleep 1
    p 2
  ensure
    p 2.5
  end
  p 3
  snooze
  p 4
  # f.stop
  # f.join
  # Fiber.current.terminate_all_children
  # Fiber.current.await_all_children
  p 5
end

puts "Child pid: #{pid}"
Process.wait(pid)