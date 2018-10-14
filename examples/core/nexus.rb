# frozen_string_literal: true

require 'modulation'

Nuclear = import('../../lib/nuclear')

async def my_sleep(t)
  puts "#{t} start"
  await Nuclear.sleep(t)
  puts "#{t} done"
end

async! do
  puts "#{Time.now} going to sleep..."
  await Nuclear.nexus do |n|
    n << my_sleep(1)
    n << my_sleep(2)
    n << my_sleep(3)
  end
  puts "#{Time.now} woke up"
end
