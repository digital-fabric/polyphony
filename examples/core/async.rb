# frozen_string_literal: true

require 'modulation'

Nuclear = import('../../lib/nuclear')

async def my_sleep(t)
  puts "going to sleep..."
  await Nuclear.sleep t
  puts "woke up"
end

spawn do
  await my_sleep(1)
end
