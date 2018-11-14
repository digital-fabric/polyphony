# frozen_string_literal: true

require 'modulation'

Rubato = import('../../lib/rubato')
LineReader  = import('../../lib/rubato/line_reader')

buffer = +''
reader = LineReader.new

Rubato.interval(0.2) { buffer << "#{Time.now.to_f}\n" }
Rubato.interval(0.3) do

  reader.push(buffer.slice!(0, buffer.bytesize / 10 * 10))
end

Rubato.async do
  reader.lines.each do |line|
    puts "* #{line}"
  end
  puts "no more lines"
end

Rubato.timeout(2) do
  Rubato.cancel_all_timers
  reader.close
end