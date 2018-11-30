# frozen_string_literal: true

require 'modulation'

Rubato = import('../../lib/rubato')

async def my_sleep(t)
  puts "start: #{t}"
  sleep(t)
  puts "done: #{t}"
end

spawn do
  puts "#{Time.now} going to sleep..."
  result = supervise do |s|
    fiber = Fiber.current
    spawn do
      sleep(0.5)
      puts "stopping supervisor..."
      s.stop!
    end
    s.spawn my_sleep(1)
    s.spawn my_sleep(2)
    s.spawn my_sleep(3)
  end
  puts "#{Time.now} woke up with #{result.inspect}"
end
