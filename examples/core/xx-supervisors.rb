# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

def my_sleep(t)
  puts "#{t} start"
  sleep(t)
  puts "#{t} done"
end

puts "#{Time.now} waiting..."
supervise do |s|
  s.spin { my_sleep(1) }
  s.spin { my_sleep(2) }
  s.spin { my_sleep(3) }
  s.spin do
    puts "fiber count: #{Fiber.count}"
  end
end
puts "#{Time.now} done waiting"
