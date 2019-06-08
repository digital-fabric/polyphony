# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

timer = spin {
  throttled_loop(5) { STDOUT << '.' }
}

puts system('ruby -e "sleep 1; puts :done; STDOUT.close"')
timer.stop
