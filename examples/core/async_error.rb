# frozen_string_literal: true

require 'modulation'

Nuclear = import('../../lib/nuclear')

async def my_sleep(t)
  raise "hello"
end

spawn do
  await my_sleep(1)
end

puts "after async"
