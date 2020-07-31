# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

timer = spin do
  throttled_loop(5) { STDOUT << '.' }
end

puts system('ruby -e "puts :sleeping; STDOUT.flush; sleep 1; puts :done"')
timer.stop
