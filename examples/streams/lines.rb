# frozen_string_literal: true

require 'modulation'

Nuclear = import('../../lib/nuclear')
LineReader  = import('../../lib/nuclear/line_reader')

buffer = +''
reader = LineReader.new

Nuclear.interval(0.2) { buffer << "#{Time.now.to_f}\n" }
Nuclear.interval(0.3) do

  reader.push(buffer.slice!(0, buffer.bytesize / 10 * 10))
end

Nuclear.async do
  reader.lines.each do |line|
    puts "* #{line}"
  end
  puts "no more lines"
end

Nuclear.timeout(2) do
  Nuclear.cancel_all_timers
  reader.close
end