# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

puts 'going to sleep...'
Timeout.timeout(1) do
  sleep 60
end
puts 'woke up'
