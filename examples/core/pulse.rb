# frozen_string_literal: true

require 'modulation'

Nuclear = import('../../lib/nuclear')

spawn do
  move_on_after(3) do
    pulse = Nuclear.pulse(1)
    while await pulse
      puts Time.now
    end
  end
  puts "done!"
end
