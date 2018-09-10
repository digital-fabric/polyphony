# frozen_string_literal: true

require 'modulation'

Nuclear = import('../../lib/nuclear')

Nuclear.async do
  generator = Nuclear.pulse(1)
  Nuclear.timeout(5) { generator.stop }
  generator.each do
    puts Time.now
  end
  puts "done with generator"
end
