# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

Exception.__disable_sanitized_backtrace__ = true

timers = 10.times.map do
  spin do
    t = Gyro::Timer.new(1, 1)
    t.await
  end
end

sleep 0.1
GC.start
sleep 0.1