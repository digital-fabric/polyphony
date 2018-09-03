# frozen_string_literal: true
require 'modulation'

Reactor = import('../../lib/nuclear/reactor')

timer_id = Reactor.interval(1) do
  puts Time.now
end

Reactor.timeout(5) do
  Reactor.cancel_timer(timer_id)
  puts "done with timer"
end
