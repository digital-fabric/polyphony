# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

Exception.__disable_sanitized_backtrace__ = true

t = Thread.new do
  async = Gyro::Async.new
  spin { async.await }
  sleep 100
end

sleep 0.5

Polyphony.fork do
  puts "forked #{Process.pid}"
  sleep 1
  puts "done sleeping"
end

sleep 50