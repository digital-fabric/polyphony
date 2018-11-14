# frozen_string_literal: true

require 'modulation'

Rubato = import('../../lib/rubato')

spawn do
  await async {
    puts "going to sleep..."
    await sleep 1
    puts "woke up"
  }
end
