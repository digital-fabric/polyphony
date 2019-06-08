# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

X = 1_000_000

# f = Fiber.new do
#   loop { Fiber.yield }
# end
# t0 = Time.now
# X.times { f.resume }
# dt = Time.now - t0
# puts "#{X / dt.to_f}/s"

# sleep
# spin do
#   t0 = Time.now
#   X.times { sleep(0) }
#   dt = Time.now - t0
#   puts "#{X / dt.to_f}/s"
# end

# snooze
spin do
  t0 = Time.now
  X.times { snooze }
  dt = Time.now - t0
  puts "#{X / dt.to_f}/s"
end
