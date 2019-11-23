# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/auto_run'

timer = spin do
  throttled_loop(5) { STDOUT << '.' }
end

puts system('ruby -e "sleep 1; puts :done; STDOUT.close"')
timer.stop
