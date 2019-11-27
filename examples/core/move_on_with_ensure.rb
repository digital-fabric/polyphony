# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/auto_run'

puts 'going to sleep...'
move_on_after(0.5) do
  t0 = Time.now
  v = sleep(60)
ensure
  puts "slept for #{Time.now - t0} seconds"
end
puts 'woke up'
