# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

puts "Write something..."
move_on_after(5) do |scope|
  loop do
    data = STDIN.readpartial(8192)
    scope.reset_timeout
    puts "you wrote: #{data}"
  end
end
puts "quitting due to inactivity"
