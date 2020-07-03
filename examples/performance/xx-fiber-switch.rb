X = 1_000_000
f = Fiber.new do
  loop { Fiber.yield }
end

t0 = Time.now
X.times { f.resume }
dt = Time.now - t0
puts "#{X / dt.to_f}/s"
