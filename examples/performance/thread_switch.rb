# frozen_string_literal: true

require 'fiber'

class Fiber
  attr_accessor :next
end

# This program shows how the performance of Fiber.transfer degrades as the fiber
# count increases

def run(num_threads)
  count = 0

  GC.start
  GC.disable

  threads = []
  t0 = Time.now
  limit = 10_000_000 / num_threads
  num_threads.times do
    threads << Thread.new do
      individual_count = 0
      loop do
        individual_count += 1
        count += 1
        break if individual_count == limit
      end
    end
  end

  threads.each(&:join)
  elapsed = Time.now - t0

  puts "threads: #{num_threads} count: #{count} rate: #{count / elapsed}"
rescue Exception => e
  puts "Stopped at #{count} threads"
  p e
end

run(100)
run(1000)
run(10000)
run(100000)
