# frozen_string_literal: true

require 'modulation'

Reactor = import('../../lib/nuclear/reactor')
extend import('../../lib/nuclear/concurrency')

timer = pulse(1)
async do
  while await timer do
    puts Time.now
  end
  puts "done with timer"
end

Reactor.timeout(5) { timer.stop }
