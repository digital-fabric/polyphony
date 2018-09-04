# frozen_string_literal: true
require 'modulation'

Concurrency = import('../../lib/nuclear/concurrency')
Reactor =     import('../../lib/nuclear/reactor')

def timeout(t)
  Concurrency.promise { |p| Reactor.timeout(t, &p) }
end

def timeout_nested
  Concurrency.await timeout(1)
  timeout(2)
end

Concurrency.async do
  t1 = Time.now
  
  result = Concurrency.await timeout_nested
  puts "elapsed! (#{Time.now - t1})"
  puts "result: #{result}"
  exit
end

Reactor.interval(1) { puts Time.now }
