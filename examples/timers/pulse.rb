# frozen_string_literal: true

require 'modulation'

Nuclear = import('../../lib/nuclear')

timer = Nuclear.pulse(1)
Nuclear.async do
  while Nuclear.await timer do
    puts Time.now
  end
  puts "done with timer"
end

Nuclear.timeout(5) { timer.stop }
