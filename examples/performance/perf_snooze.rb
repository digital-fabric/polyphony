# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

X = 1_000_000

STDOUT << "Fiber.yield: "
f = Fiber.new do
  loop { Fiber.yield }
end
t0 = Time.now
X.times { f.resume }
dt = Time.now - t0
puts "%d/s" % (X / dt)

# STDOUT << "Kernel#sleep: "
# t0 = Time.now
# X.times { sleep(0) }
# dt = Time.now - t0
# puts "%d/s" % (X / dt)

STDOUT << "Kernel#snooze: "
t0 = Time.now
X.times { snooze }
dt = Time.now - t0
puts "%d/s" % (X / dt)