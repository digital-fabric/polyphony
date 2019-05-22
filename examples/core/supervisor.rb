# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

async def my_sleep(t)
  puts "#{t} start"
  sleep(t)
  puts "#{t} done"
end

puts "#{Time.now} waiting..."
supervise do |s|
  s.spawn my_sleep(1)
  s.spawn my_sleep(2)
  s.spawn my_sleep(3)
  s.spawn {
    puts "fiber count: #{Polyphony::FiberPool.size}"
  }
end
puts "#{Time.now} done waiting"
