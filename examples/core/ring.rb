# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

M = 100
N = 10000

GC.disable

def monotonic_clock
  ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
end

def spin_proc(next_fiber)
  spin_loop { next_fiber << receive }
end

last = Fiber.current
N.times { last = spin_proc(last) }

snooze
t0 = monotonic_clock
M.times do
  last << 'hello'
  receive
end
elapsed = monotonic_clock - t0
puts "M=#{M} N=#{N} elapsed: #{elapsed}"
