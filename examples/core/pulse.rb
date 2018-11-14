# frozen_string_literal: true

require 'modulation'

Rubato = import('../../lib/rubato')

spawn do
  move_on_after(3) do
    pulser = pulse(1)
    while await pulser
      puts Time.now
    end
  end
  puts "done!"
end
