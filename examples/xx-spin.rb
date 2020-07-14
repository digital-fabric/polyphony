# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

puts "pid: #{Process.pid}"
GC.disable

def mem_usage
  # orig_backtick('ps -o rss #{$$}').split.last.to_i
  `ps -o rss #{$$}`.split.last.to_i
end

f = File.open('spin.log', 'w+')

m0 = mem_usage

X = ARGV[0] ? ARGV[0].to_i : 10
STDOUT.orig_write "Starting #{X} fibers...\n"
t0 = Time.now
x = nil
X.times do |i|
  spin { p i; suspend }
end

suspend
f.close
t1 = Time.now
m1 = mem_usage
rate = X / (t1 - t0)
mem_cost = (m1 - m0) / X.to_f
STDOUT.orig_write("#{ { time: t1 - t0, spin_rate: rate, fiber_mem_cost: mem_cost }.inspect }\n")
