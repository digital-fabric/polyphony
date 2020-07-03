require 'bundler/setup'
require 'polyphony'

Y = ARGV[0] ? ARGV[0].to_i : 1

count = 0
Y.times do
  spin { loop { count += 1; snooze } }
end

t0 = Time.now
sleep 10
elapsed = Time.now - t0
rate = count / elapsed
puts "concurrency: #{Y} rate: #{rate} switchpoints per second"
