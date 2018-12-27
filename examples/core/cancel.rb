# frozen_string_literal: true

require 'modulation'

Rubato = import('../../lib/rubato')

puts "going to sleep..."
cancel_after(1) do
  sleep(60)
end
