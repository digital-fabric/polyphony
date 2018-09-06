# frozen_string_literal: true

require 'modulation'

Core = import('../../lib/nuclear/core')
include Core::Async

def timeout(t)
  promise do |p|
    Core::Reactor.timeout(t) { p.error(RuntimeError.new("hello")) }
  end
end

async do
  t1 = Time.now
  
  result = await timeout(2), timeout(1), timeout(3)
  puts "elapsed! (#{Time.now - t1})"
  puts "result: #{result}"
  exit
end

Core::Reactor.interval(1) { puts Time.now }
