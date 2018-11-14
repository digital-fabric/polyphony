# frozen_string_literal: true

require 'modulation'

Rubato = import('../../lib/rubato')

async def sleep_and_cancel
  puts "going to sleep..."
  move_on_after(0.5) do
    begin
      await sleep 60
    ensure
      puts "in ensure (is it going to block?)"
      # this should not block, since we're still in the scope, and it was cancelled
      await sleep 10
    end
  end
  puts "woke up"
end

spawn sleep_and_cancel