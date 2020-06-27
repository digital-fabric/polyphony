# frozen_string_literal: true

require 'bundler/setup'
require 'irb'
require 'polyphony/adapters/irb'

$counter = 0
timer = spin do
  throttled_loop(5) do
    $counter += 1
  end
end

at_exit { timer.stop }

puts 'try typing $counter to see the counter incremented in the background'
IRB.start
