# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

def bm(fibers, iterations)
  count = 0
  t_pre = Time.now
  fibers.times do
    spin do
      iterations.times do
        snooze
        count += 1
      end
    end
  end
  t0 = Time.now
  Fiber.current.await_all_children
  dt = Time.now - t0
  puts "#{[fibers, iterations].inspect} setup: #{t0 - t_pre}s count: #{count} #{count / dt.to_f}/s"
  Thread.current.run_queue_trace
end

GC.disable

bm(1, 1_000_000)
bm(10, 100_000)
bm(100, 10_000)
bm(1_000, 1_000)
bm(10_000, 100)

# bm(100_000,    10)
# bm(1_000_000,   1)
