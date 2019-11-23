# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/auto_run'
require 'irb'

# For some reason, this example does not work

$counter = 0
timer = spin do
  throttled_loop(1) { $counter += 1; p Time.now }
end

at_exit { timer.stop }

IRB.start
