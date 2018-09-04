# frozen_string_literal: true
require 'modulation'

Concurrency = import('../../lib/nuclear/concurrency')
Reactor =     import('../../lib/nuclear/reactor')

def timeout(t)
  Concurrency.promise do |p|
    Reactor.timeout(t) { p.error(RuntimeError.new("hello")) }
  end
end

Concurrency.async do
  t1 = Time.now
  
  result = Concurrency.await timeout(2), timeout(1), timeout(3)
  puts "elapsed! (#{Time.now - t1})"
  puts "result: #{result}"
  exit
end

Reactor.interval(1) { puts Time.now }
