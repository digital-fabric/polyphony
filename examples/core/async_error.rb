# frozen_string_literal: true

require 'modulation'

Rubato = import('../../lib/rubato')

async def my_sleep(t)
  raise "hello"
end

spawn do
  await my_sleep(1)
end

puts "after async"
