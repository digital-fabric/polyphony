# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

puts 'going to sleep...'
move_on_after(0.5) do |scope|
  sleep 60
ensure
  puts 'in ensure (is it going to block?)'
  # this should not block, since the scope was cancelled
  sleep 10 unless scope.cancelled?
end
puts 'woke up'
