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
  puts "start transfer..."
  first.transfer
  elapsed = Time.now - t0

  rss = `ps -o rss= -p #{Process.pid}`.to_i

  puts "fibers: #{num_fibers} rss: #{rss} count: #{count} rate: #{count / elapsed}"
rescue Exception => e
  puts "Stopped at #{count} fibers"
  p e
end

puts "pid: #{Process.pid}"
run(100)
# run(1000)
# run(10000)
# run(100000)
# run(400000)
