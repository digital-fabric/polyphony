# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/auto_run'

def bm(fibers, iterations)
  count = 0
  t0 = Time.now
  supervise do |s|
    fibers.times do
      s.spin do
        iterations.times { snooze; count += 1 }
      end
    end
  end
  dt = Time.now - t0
  puts "#{[fibers, iterations].inspect} count: #{count} #{count / dt.to_f}/s"
end

bm(1, 1000000)
bm(10, 100000)
bm(100, 10000)
bm(1000, 1000)
bm(10000, 100)
# bm(100000, 10)
# bm(1000000, 1)
