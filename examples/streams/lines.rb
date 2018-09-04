# frozen_string_literal: true
require 'modulation'

Concurrency = import('../../lib/nuclear/concurrency')
Reactor =     import('../../lib/nuclear/reactor')
LineReader =  import('../../lib/nuclear/line_reader')

buffer = +''
reader = LineReader.new

Reactor.interval(0.2) { buffer << "#{Time.now.to_f}\n" }
Reactor.interval(0.3) do

  reader.push(buffer.slice!(0, buffer.bytesize / 10 * 10))
end

Concurrency.async do
  reader.lines.each do |line|
    puts "* #{line}"
  end
  puts "no more lines"
end

Reactor.timeout(2) do
  Reactor.cancel_all_timers
  reader.close
end