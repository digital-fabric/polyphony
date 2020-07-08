# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

Exception.__disable_sanitized_backtrace__ = true

puts "pid: #{Process.pid}"

Process.daemon(true, true)

Polyphony::ThreadPool.process do
  puts "Hello world from pid #{Process.pid}"
end