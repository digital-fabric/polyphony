# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

async def my_sleep(t)
  puts "start: #{t}"
  r = sleep(t)
  puts "my_sleep result #{r.inspect}"
  puts "done: #{t}"
end

puts "#{Time.now} going to sleep..."
move_on_after(0.5) do
  supervise do |s|
    puts "supervise block"
    s.spawn my_sleep(1)
    s.spawn my_sleep(2)
    s.spawn my_sleep(3)
  end
  puts "supervisor done"
end
puts "#{Time.now} woke up"
