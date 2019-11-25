# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/auto_run'

move_on_after(3) do
  puts "Start..."
  pulser = pulse(1)
  puts Time.now while pulser.await
end
puts 'done!'
