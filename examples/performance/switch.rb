# frozen_string_literal: true

require 'fiber'

X = 10_000_000

main = Fiber.current
f = Fiber.new do
  loop { main.transfer }
end

t0 = Time.now
X.times { f.transfer }
dt = Time.now - t0
puts "#{X / dt.to_f}/s"
puts fs.size