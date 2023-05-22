# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'
require "benchmark/ips"

class Fiber
  def call(*a, **b)
    self << [Fiber.current, a, b]
    Fiber.current.receive
  end

  def respond
    peer, a, b = receive
    result = yield(*a, **b)
    (peer << result) rescue nil
  rescue
    peer.raise(result)
  end

  def respond_loop(&b)
    while true
      respond(&b)
    end
  end
end

$server = spin do
  Fiber.current.respond_loop do |x, y|
    x * y
  end
end

$server_optimized = spin do
  while true
    fiber, x, y = receive
    fiber << (x * y)
  end
end

peer = Fiber.current
$server_single = spin do
  while true
    x = receive
    peer << x * 4
  end
end

$server_schedule = spin do
  while true
    x = suspend
    peer.schedule x * 4
  end
end

$server_raw = Fiber.new do |x|
  while true
    x = peer.transfer x * 4
  end
end

def calc(x, y)
  x * y
end

def bm_raw
  calc(3, 4)
end

def bm_send
  send(:calc, 3, 4)
end

def bm_fiber
  $server.call(3, 4)
end

def bm_fiber_optimized
  $server_optimized << [Fiber.current, 3, 4]
  receive
end

def bm_fiber_single
  $server_single << 3
  receive
end

def bm_fiber_schedule
  $server_schedule.schedule(3)
  suspend
end

def bm_fiber_raw
  $server_raw.transfer 3
end

p bm_raw
p bm_send
p bm_fiber
p bm_fiber_optimized
p bm_fiber_single
p bm_fiber_raw
p bm_fiber_schedule

def warmup_jit
  10000.times do
    bm_raw
    bm_send
    bm_fiber
    bm_fiber_optimized
    bm_fiber_single
    bm_fiber_raw
    bm_fiber_schedule
  end
end

puts "warming up JIT..."

3.times do
  warmup_jit
  sleep 1
end

Benchmark.ips do |x|
  x.report("raw") { bm_raw }
  x.report("send") { bm_send }
  x.report("fiber") { bm_fiber }
  x.report("fiber_optimized") { bm_fiber_optimized }
  x.report("fiber_single") { bm_fiber_single }
  x.report("fiber_raw") { bm_fiber_raw }
  x.report("fiber_schedule") { bm_fiber_schedule }
  x.compare!
end

# p call_result: server.call(3, 4)

