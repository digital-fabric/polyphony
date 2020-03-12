# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

trap('TERM') do
  # do nothing
end

trap('INT') do
  # do nothing
end

puts "go to sleep"
begin
  sleep
ensure
  puts "done sleeping"
end