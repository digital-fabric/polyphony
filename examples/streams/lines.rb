# frozen_string_literal: true
require 'modulation'

Core        = import('../../lib/nuclear/core')
LineReader  = import('../../lib/nuclear/line_reader')
include Core::Async

buffer = +''
reader = LineReader.new

Core::Reactor.interval(0.2) { buffer << "#{Time.now.to_f}\n" }
Core::Reactor.interval(0.3) do

  reader.push(buffer.slice!(0, buffer.bytesize / 10 * 10))
end

async do
  reader.lines.each do |line|
    puts "* #{line}"
  end
  puts "no more lines"
end

Core::Reactor.timeout(2) do
  Core::Reactor.cancel_all_timers
  reader.close
end