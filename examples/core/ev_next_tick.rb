# frozen_string_literal: true

require 'modulation'

Nuclear = import('../../lib/nuclear')

EV.next_tick do
  puts "hello from next_tick"
  EV.next_tick { puts "111" }
end

EV::Timer.new(1, 1) { puts Time.now }