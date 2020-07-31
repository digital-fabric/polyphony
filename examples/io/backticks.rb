# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

timer = spin do
  throttled_loop(5) { STDOUT << '.' }
end

puts `ruby -e "sleep 1; puts :done; STDOUT.close"`
timer.stop
