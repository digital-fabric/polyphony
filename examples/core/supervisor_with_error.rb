# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/auto_run'
require 'polyphony/extensions/backtrace'

def my_sleep(t)
  sleep(t)
  raise 'blah'
end

spin do
  puts "#{Time.now} going to sleep..."
  supervise do |s|
    s.spin { my_sleep(1) }
    s.spin { my_sleep(2) }
    s.spin { my_sleep(3) }
  end
# rescue StandardError => e
#   puts "exception from supervisor: #{e}"
ensure
  puts "#{Time.now} woke up"
end
