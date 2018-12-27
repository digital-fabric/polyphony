# frozen_string_literal: true

require 'modulation'

Rubato = import('../../lib/rubato')

move_on_after(3) do
  pulser = pulse(1)
  while pulser.await
    puts Time.now
  end
end
puts "done!"
