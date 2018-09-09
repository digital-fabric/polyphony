# frozen_string_literal: true

require 'modulation'

Nuclear = import('../../lib/nuclear')

def count_to(x)
  Nuclear.generator do |promise|
    count = 0
    counter = proc {
      count += 1
      promise.resolve(count)
      Nuclear.timeout(0.05 + rand * 0.05) { counter.() } unless count == x
    }
    Nuclear.timeout(0.05, &counter)
  end
end

Nuclear.async do
  generator = count_to(10)
  generator.each do |i|
    puts "count: #{i}"
  end
end
