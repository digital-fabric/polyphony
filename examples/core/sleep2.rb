# frozen_string_literal: true

require 'modulation'

Nuclear = import('../../lib/nuclear')

spawn do
  await async {
    puts "going to sleep..."
    await sleep 1
    puts "woke up"
  }
end
