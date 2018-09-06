# frozen_string_literal: true
require 'modulation'

Core = import('../../lib/nuclear/core')
include Core::Async

async do
  generator = pulse(1)
  Core::Reactor.timeout(5) { generator.stop }
  generator.each do
    puts Time.now
  end
  puts "done with generator"
end
