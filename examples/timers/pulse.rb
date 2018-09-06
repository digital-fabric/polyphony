# frozen_string_literal: true

require 'modulation'

Core = import('../../lib/nuclear/core')
include Core::Async

timer = pulse(1)
async do
  while await timer do
    puts Time.now
  end
  puts "done with timer"
end

Core::Reactor.timeout(5) { timer.stop }
