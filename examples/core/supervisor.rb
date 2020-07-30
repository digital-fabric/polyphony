# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

def my_sleep(t)
  puts "#{t} start"
  sleep(t)
  puts "#{t} done"
end

spin { my_sleep(1) }
spin { my_sleep(2) }
spin { my_sleep(3) }
spin { puts "fiber count: #{Fiber.current.children.count}" }
snooze

puts "#{Time.now} supervising..."
supervise
puts "#{Time.now} done supervising"
