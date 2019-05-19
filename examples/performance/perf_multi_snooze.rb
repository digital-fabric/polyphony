# frozen_string_literal: true

require 'modulation'
Polyphony = import('../../lib/polyphony')

ITERATIONS  = 1_000
FIBERS      = 1_000

spawn do
  count = 0
  t0 = Time.now
  supervise do |s|
    FIBERS.times do
      s.spawn do
        ITERATIONS.times { snooze; count += 1 }
      end
    end
  end
  dt = Time.now - t0
  puts "count: #{count} #{count / dt.to_f}/s"
end