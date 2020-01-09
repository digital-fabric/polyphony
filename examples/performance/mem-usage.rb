require 'fiber'

def mem_usage
  `ps -o rss #{$$}`.split.last.to_i
end

def calculate_fiber_memory_cost(count)
  GC.disable
  rss0 = mem_usage
  count.times { Fiber.new { sleep 1 } }
  rss1 = mem_usage
  GC.start
  cost = (rss1 - rss0).to_f / count

  puts "fiber memory cost: #{cost}KB"
end

calculate_fiber_memory_cost(10000)

def calculate_thread_memory_cost(count)
  GC.disable
  rss0 = mem_usage
  count.times { Thread.new { sleep 1 } }
  sleep 0.5
  rss1 = mem_usage
  sleep 0.5
  GC.start
  cost = (rss1 - rss0).to_f / count

  puts "thread memory cost: #{cost}KB"
end

calculate_thread_memory_cost(500)

require 'bundler/setup'
require 'polyphony'

def calculate_extended_fiber_memory_cost(count)
  GC.disable
  rss0 = mem_usage
  count.times { spin { :foo } }
  snooze
  rss1 = mem_usage
  GC.start
  cost = (rss1 - rss0).to_f / count

  puts "extended fiber memory cost: #{cost}KB"
end

calculate_extended_fiber_memory_cost(10000)