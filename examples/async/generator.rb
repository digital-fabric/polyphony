# frozen_string_literal: true
require 'modulation'

Concurrency = import('../../lib/nuclear/concurrency')
Reactor =     import('../../lib/nuclear/reactor')

def count_to(x)
  Concurrency.generator do |promise|
    count = 0
    counter = proc {
      count += 1
      promise.resolve(count)
      Reactor.timeout(0.1 + rand * 0.1) { counter.() } unless count == x
    }
    Reactor.timeout(0.1, &counter)
  end
end

Concurrency.async do
  generator = count_to(10)
  generator.each do |i|
    puts "count: #{i}"
  end
end
