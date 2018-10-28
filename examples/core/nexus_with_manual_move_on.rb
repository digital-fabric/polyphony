# frozen_string_literal: true

require 'modulation'

Nuclear = import('../../lib/nuclear')

async def my_sleep(t)
  puts "start: #{t}"
  await sleep(t)
  puts "done: #{t}"
end

spawn do
  puts "#{Time.now} going to sleep..."
  result = await Nuclear.nexus do |n|
    fiber = Fiber.current
    spawn do
      await sleep(0.5)
      n.move_on!(42)
    end
    n << my_sleep(1)
    n << my_sleep(2)
    n << my_sleep(3)
  end
  puts "#{Time.now} woke up with #{result.inspect}"
end
