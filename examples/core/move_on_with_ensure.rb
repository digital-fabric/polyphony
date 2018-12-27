# frozen_string_literal: true

require 'modulation'

Rubato = import('../../lib/rubato')

puts "going to sleep..."
move_on_after(0.5) do |scope|
  begin
    sleep 60
  ensure
    puts "in ensure (is it going to block?)"
    # this should not block, since the scope was cancelled
    sleep 10 unless scope.cancelled?
  end
end
puts "woke up"
