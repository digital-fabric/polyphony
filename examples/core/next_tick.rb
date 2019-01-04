# frozen_string_literal: true

require 'modulation'

Polyphony = import('../../lib/polyphony')

EV.next_tick do
  puts "two"
  EV.next_tick { puts "four" }
  puts "three"
end

puts "one"