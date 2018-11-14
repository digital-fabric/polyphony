# frozen_string_literal: true

require 'modulation'

Rubato = import('../../lib/rubato')

async def sleep_and_cancel
  puts "going to sleep..."
  move_on_after(1) do
    await sleep 60
  end
  puts "woke up"
end

spawn sleep_and_cancel