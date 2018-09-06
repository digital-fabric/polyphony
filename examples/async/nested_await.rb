# frozen_string_literal: true

require 'modulation'

Core = import('../../lib/nuclear/core')
include Core::Async

def timeout(t)
  promise { |p| Core::Reactor.timeout(t, &p) }
end

def timeout_nested
  await timeout(1)
  timeout(2)
end

async do
  t1 = Time.now
  
  result = await timeout_nested
  puts "elapsed! (#{Time.now - t1})"
  puts "result: #{result}"
  exit
end

Core::Reactor.interval(1) { puts Time.now }
