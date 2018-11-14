# frozen_string_literal: true

require 'modulation'

Rubato = import('../../lib/rubato')

EV.next_tick do
  puts "hello from next_tick"
  EV.next_tick { puts "111" }
end

Rubato.every(1) { puts Time.now }