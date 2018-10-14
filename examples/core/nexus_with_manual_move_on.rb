# frozen_string_literal: true

require 'modulation'

Nuclear = import('../../lib/nuclear')

async def my_sleep(t)
  puts "start: #{t}"
  await Nuclear.sleep(t)
  puts "done: #{t}"
end

async! do
  puts "#{Time.now} going to sleep..."
  result = await Nuclear.nexus do |n|
    fiber = Fiber.current
    async! do
      await Nuclear.sleep(0.5)
      n.move_on!(42)
    end
    n << my_sleep(1)
    n << my_sleep(2)
    n << my_sleep(3)
  end
  puts "#{Time.now} woke up with #{result.inspect}"
end
