# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

Exception.__disable_sanitized_backtrace__ = true
Thread.event_selector = Gyro::Selector
Thread.current.setup_fiber_scheduling

def bm(fibers, iterations)
  count = {}

  t0 = Time.now
  threads = (1..1).map do |i|
    Thread.new do
      count[i] = 0
      supervise do |s|
        fibers.times do
          s.spin do
            iterations.times do
              snooze
              count[i] += 1
            end
          end
        end
      end
    end
  end
  threads.each(&:join)
  dt = Time.now - t0
  count = count.values.inject(0, &:+)
  puts "#{[fibers, iterations].inspect} count: #{count} #{count / dt.to_f}/s"
end

# GC.disable

loop {
  puts "*" * 60
  bm(1, 1_000_000)
  bm(10,  100_000)
  bm(100,  10_000)
  bm(1_000, 1_000)
  bm(10_000,  100)
  bm(100_000,  10)
  # bm(1_000_000, 1)
}
