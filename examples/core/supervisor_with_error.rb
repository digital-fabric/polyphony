# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

async def my_sleep(t)
  sleep(t)
  raise "blah"
end

coproc do
  puts "#{Time.now} going to sleep..."
  supervise do |s|
    s.coproc my_sleep(1)
    s.coproc my_sleep(2)
    s.coproc my_sleep(3)
  end
rescue => e
  puts "exception from supervisor: #{e}"
ensure
  puts "#{Time.now} woke up"
end
