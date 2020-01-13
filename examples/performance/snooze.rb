# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

X = 1_000_000

GC.disable

STDOUT << 'Fiber.yield:      '
f = Fiber.new do
  loop { Fiber.yield }
end
t0 = Time.now
X.times { f.resume }
dt = Time.now - t0
puts format('%d/s', (X / dt))

STDOUT << 'Fiber.transfer:   '
main = Fiber.current
f = Fiber.new do
  loop { main.transfer }
end
t0 = Time.now
X.times { f.transfer }
dt = Time.now - t0
puts format('%d/s', (X / dt))

STDOUT << 'Kernel#snooze:    '
t0 = Time.now
X.times { snooze }
dt = Time.now - t0
puts format('%d/s', (X / dt))

# STDOUT << 'Kernel#sleep:     '
# t0 = Time.now
# X.times { sleep(0) }
# dt = Time.now - t0
# puts "%d/s" % (X / dt)
