require 'fiber'

def mem_usage
  `ps -o rss #{$$}`.split.last.to_i
end

def calculate_memory_cost(name, count, &block)
  GC.enable
  ObjectSpace.garbage_collect
  sleep 0.5
  GC.disable
  rss0 = mem_usage
  count0 = ObjectSpace.count_objects[:TOTAL] - ObjectSpace.count_objects[:FREE]
  a = []
  count.times { a << block.call }
  rss1 = mem_usage
  count1 = ObjectSpace.count_objects[:TOTAL] - ObjectSpace.count_objects[:FREE]
  p [count0, count1]
  # sleep 0.5
  cost = (rss1 - rss0).to_f / count
  count_delta = (count1 - count0) / count

  puts "#{name} rss cost: #{cost}KB     object count: #{count_delta}"
end

f = Fiber.new { |f| f.transfer }
f.transfer Fiber.current

calculate_memory_cost('fiber', 10000) do
  f = Fiber.new { |f| f.transfer :foo }
  f.transfer Fiber.current
  f
end

t = Thread.new { sleep 1}
t.kill
t.join

calculate_memory_cost('thread', 500) do
  t = Thread.new { sleep 1 }
  sleep 0.001
  t
end
(Thread.list - [Thread.current]).each(&:kill).each(&:join)

require 'bundler/setup'
require 'polyphony'

f = spin { sleep 0.1 }
f.await

calculate_memory_cost('polyphony fiber', 10000) do
  f = spin { :foo }
  f.await
  f
end
