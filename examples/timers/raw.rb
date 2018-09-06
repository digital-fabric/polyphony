# frozen_string_literal: true
require 'modulation'

Core = import('../../lib/nuclear/core')

timer_id = Core::Reactor.interval(1) do
  puts Time.now
end

Core::Reactor.timeout(5) do
  Core::Reactor.cancel_timer(timer_id)
  puts "done with timer"
end
