# frozen_string_literal: true

require 'modulation'

Rubato = import('../../lib/rubato')

async def my_sleep(t)
  puts "start: #{t}"
  await sleep(t)
  puts "done: #{t}"
end

spawn do
  puts "#{Time.now} going to sleep..."
  result = await supervise do |s|
    fiber = Fiber.current
    spawn do
      await sleep(0.5)
      puts "stopping supervisor..."
      s.stop!
    end
    s << my_sleep(1)
    s << my_sleep(2)
    s << my_sleep(3)
  end
  puts "#{Time.now} woke up with #{result.inspect}"
end
