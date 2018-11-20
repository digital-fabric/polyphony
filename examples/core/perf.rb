# frozen_string_literal: true

require 'modulation'
Rubato = import('../../lib/rubato')

X = 1_000_000

# f = Fiber.new do
#   loop { Fiber.yield }
# end
# t0 = Time.now
# X.times { f.resume }
# dt = Time.now - t0
# puts "#{X / dt.to_f}/s"

# sleep
# spawn do
#   t0 = Time.now
#   X.times { await sleep(0) }
#   dt = Time.now - t0
#   puts "#{X / dt.to_f}/s"
# end

# snooze
spawn do
  t0 = Time.now
  X.times { EV.snooze }
  dt = Time.now - t0
  puts "#{X / dt.to_f}/s"
end