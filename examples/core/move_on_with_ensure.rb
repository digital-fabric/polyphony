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
      # this will also obey the cancel scope
      await sleep 10
    end
  end
  puts "woke up"
end

spawn sleep_and_cancel