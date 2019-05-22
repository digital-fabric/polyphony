# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

move_on_after(3) do
  pulser = pulse(1)
  while pulser.await
    puts Time.now
  end
end
puts "done!"
