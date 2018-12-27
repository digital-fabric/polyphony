# frozen_string_literal: true

require 'modulation'

Rubato = import('../../lib/rubato')

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
    puts "fiber count: #{Rubato::FiberPool.size}"
  }
end
puts "#{Time.now} done waiting"
