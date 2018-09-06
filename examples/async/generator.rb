# frozen_string_literal: true

require 'modulation'

Core = import('../../lib/nuclear/core')
include Core::Async

def count_to(x)
  generator do |promise|
    count = 0
    counter = proc {
      count += 1
      promise.resolve(count)
      Core::Reactor.timeout(0.1 + rand * 0.1) { counter.() } unless count == x
    }
    Core::Reactor.timeout(0.1, &counter)
  end
end

async do
  generator = count_to(10)
  generator.each do |i|
    puts "count: #{i}"
  end
end
