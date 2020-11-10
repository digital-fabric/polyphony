# frozen_string_literal: true

require 'fiber'

class Fiber
  attr_accessor :next
end

# This program shows how the performance of Fiber.transfer degrades as the fiber
# count increases

def run(num_fibers)
  count = 0

  GC.start
  GC.disable

  fibers = []
  num_fibers.times do
    fibers << Fiber.new { loop { Fiber.yield } }
  end

  t0 = Time.now

  while count < 1000000
    fibers.each do |f|
      count += 1
      f.resume
    end
  end

  elapsed = Time.now - t0

  puts "fibers: #{num_fibers} count: #{count} rate: #{count / elapsed}"
rescue Exception => e
  puts "Stopped at #{count} fibers"
  p e
end

run(100)
run(1000)
run(10000)
run(100000)
