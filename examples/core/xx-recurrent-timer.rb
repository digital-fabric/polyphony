# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

move_on_after(3.1) do
  puts 'Start...'
  every(1) do
    puts Time.now
  end
end
puts 'done!'
