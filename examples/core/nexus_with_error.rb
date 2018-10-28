# frozen_string_literal: true

require 'modulation'

Nuclear = import('../../lib/nuclear')

async def my_sleep(t)
  await sleep(t)
  raise "blah"
end

spawn do
  puts "#{Time.now} going to sleep..."
  result = await Nuclear.nexus do |f|
    f << my_sleep(1)
    f << my_sleep(2)
    f << my_sleep(3)
  end
rescue => e
  puts "exception from nexus: #{e}"
ensure
  puts "#{Time.now} woke up"
end
