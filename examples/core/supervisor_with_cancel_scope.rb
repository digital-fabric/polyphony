# frozen_string_literal: true

require 'modulation'

Rubato = import('../../lib/rubato')

async def my_sleep(t)
  puts "start: #{t}"
  r = await sleep(t)
  puts "my_sleep result #{r.inspect}"
  puts "done: #{t}"
end

spawn do
  puts "#{Time.now} going to sleep..."
  move_on_after(0.5) do
    await supervise do |s|
      s << my_sleep(1)
      s << my_sleep(2)
      s << my_sleep(3)
    end
    puts "supervisor done"
  end
  puts "#{Time.now} woke up"
end
