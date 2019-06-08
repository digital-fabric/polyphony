# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'
require 'irb'

$counter = 0

timer = spin do
  throttled_loop(10) { $counter += 1 }
end

at_exit { timer.stop }

IRB.start