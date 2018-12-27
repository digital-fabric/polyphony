# frozen_string_literal: true

require 'modulation'

Rubato = import('../../lib/rubato')

EV.next_tick do
  puts "two"
  EV.next_tick { puts "four" }
  puts "three"
end

puts "one"