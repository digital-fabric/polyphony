# frozen_string_literal: true

require 'fiber'

class Fiber
  attr_accessor :next
end

# This program shows how the performance 

def run(num_fibers)
  count = 0

  GC.disable

  first = nil
  last = nil
  supervisor = Fiber.current
  num_fibers.times do
    fiber = Fiber.new do
      loop do
        count += 1
        if count == 1_000_000
          supervisor.transfer
        else
          Fiber.current.next.transfer
        end
      end
    end
    first ||= fiber
    last.next = fiber if last
    last = fiber
  end

  last.next = first
  
  t0 = Time.now
  first.transfer
  elapsed = Time.now - t0

  puts "fibers: #{num_fibers} count: #{count} rate: #{count / elapsed}"
  GC.start
end

run(100)
run(1000)
run(10000)