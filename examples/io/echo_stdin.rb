# frozen_string_literal: true

require 'modulation'

Polyphony = import('../../lib/polyphony')

puts "Write something..."
move_on_after(5) do |scope|
  loop do
    data = STDIN.read
    scope.reset_timeout
    puts "you wrote: #{data}"
  end
end
puts "quitting due to inactivity"
