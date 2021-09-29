# frozen_string_literal: true

require "benchmark/ips"

def slice
  str = ('*' * 40) + "\n" + ('*' * 40) + "\n" + ('*' * 40) + "\n" + ('*' * 40) + "\n" + ('*' * 40)
  lines = []
  while true
    idx = str.index("\n")
    break unless idx

    lines << str.slice!(0, idx + 1)
  end
  raise unless lines.size == 4
  raise unless str == ('*' * 40)
end

def split
  str = ('*' * 40) + "\n" + ('*' * 40) + "\n" + ('*' * 40) + "\n" + ('*' * 40) + "\n" + ('*' * 40)
  lines = str.split("\n")
  if str[-1] == "\n"
    str = ''
  else
    str = lines.pop
  end
  raise unless lines.size == 4
  raise unless str == ('*' * 40)
end

Benchmark.ips do |x|
  x.report("slice") { slice }
  x.report("split") { split }
  x.compare!
end
