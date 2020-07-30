# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

puts "going to sleep (press Ctrl-C to stop)"
begin
  sleep
ensure
  puts "done sleeping"
end
