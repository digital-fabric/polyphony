# frozen_string_literal: true

require 'modulation'

Core = import('../../lib/nuclear/core')
include Core::Async

def timeout(t)
  promise { |p| Core::Reactor.timeout(t, &p) }
end

async do
  t1 = Time.now
  
  result = await *[2, 1.5, 3].map(&method(:timeout))
  puts "elapsed! (#{Time.now - t1})"
  puts "result: #{result}"
  exit
end

Core::Reactor.interval(1) { puts Time.now }
