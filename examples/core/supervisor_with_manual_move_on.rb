# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/auto_run'

def my_sleep(t)
  puts "start: #{t}"
  sleep(t)
  puts "done: #{t}"
end

puts "#{Time.now} going to sleep..."
result = supervise do |s|
  spin do
    sleep(0.5)
    puts 'stopping supervisor...'
    s.stop!
  end
  s.spin { my_sleep(1) }
  s.spin { my_sleep(2) }
  s.spin { my_sleep(3) }
end
puts "#{Time.now} woke up with #{result.inspect}"
