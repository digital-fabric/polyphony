# frozen_string_literal: true

require 'modulation'
Rubato = import('../../lib/rubato')

ITERATIONS  = 1_000
FIBERS      = 1_000

spawn do
  t0 = Time.now
  supervise do |s|
    FIBERS.times do
      s.spawn do
        ITERATIONS.times { EV.snooze }
      end
    end
  end
  dt = Time.now - t0
  puts "#{(ITERATIONS * FIBERS) / dt.to_f}/s"
end