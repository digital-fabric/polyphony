# frozen_string_literal: true

require 'modulation'

Polyphony = import('../../lib/polyphony')
LineReader  = import('../../lib/polyphony/line_reader')

buffer = +''
reader = LineReader.new

Polyphony.interval(0.2) { buffer << "#{Time.now.to_f}\n" }
Polyphony.interval(0.3) do

  reader.push(buffer.slice!(0, buffer.bytesize / 10 * 10))
end

Polyphony.async do
  reader.lines.each do |line|
    puts "* #{line}"
  end
  puts "no more lines"
end

Polyphony.timeout(2) do
  Polyphony.cancel_all_timers
  reader.close
end