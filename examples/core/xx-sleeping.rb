# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

Exception.__disable_sanitized_backtrace__ = true

# spin {
#   10.times {
#     STDOUT << '.'
#     sleep 0.1
#   }
# }

puts 'going to sleep...'
sleep 1
puts 'woke up'

counter = 0
t = Polyphony::Throttler.new(5)
t.process do
  p counter
  counter += 1
  t.stop if counter > 5
end
