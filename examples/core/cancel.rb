# frozen_string_literal: true

require 'modulation'

Polyphony = import('../../lib/polyphony')

puts "going to sleep..."
cancel_after(1) do
  sleep(60)
end
