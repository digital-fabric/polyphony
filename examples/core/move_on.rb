# frozen_string_literal: true

require 'modulation'

Rubato = import('../../lib/rubato')

puts "going to sleep..."
move_on_after(1) do
  sleep 60
end
puts "woke up"
