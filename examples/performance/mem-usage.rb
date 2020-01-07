require 'fiber'

def mem_usage
  `ps -o rss #{$$}`.strip.split.last.to_i
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

require 'bundler/setup'
require 'polyphony'

def calculate_coprocess_memory_cost(count)
  GC.disable
  rss0 = mem_usage
  count.times { spin { :foo } }
  snooze
  rss1 = mem_usage
  GC.start
  cost = (rss1 - rss0).to_f / count

  puts "coprocess memory cost: #{cost}KB"
end

calculate_coprocess_memory_cost(10000)