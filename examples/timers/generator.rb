# frozen_string_literal: true
require 'modulation'

Reactor = import('../../lib/nuclear/reactor')

extend import('../../lib/nuclear/concurrency')

async do
  generator = pulse(1)
  Reactor.timeout(5) { generator.stop }
  generator.each do
    puts Time.now
  end
  puts "done with generator"
end
