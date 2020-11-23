# frozen_string_literal: true

require 'benchmark'

LIMIT = 1_000_0

def do_while
  i = 0
  while true
    i += 1
    break if i == LIMIT
  end
end

def do_loop
  i = 0
  loop do
    i += 1
    break if i == LIMIT
  end
end

GC.disable
Benchmark.bm do |x|
  x.report('while') do
    LIMIT.times { do_while }
  end
  x.report('loop') do
    LIMIT.times { do_loop }
  end
end

