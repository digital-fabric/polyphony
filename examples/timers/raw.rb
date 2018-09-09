# frozen_string_literal: true
require 'modulation'

Nuclear = import('../../lib/nuclear')

timer_id = Nuclear.interval(1) do
  puts Time.now
end

Nuclear.timeout(5) do
  Nuclear.cancel_timer(timer_id)
  puts "done with timer"
end
