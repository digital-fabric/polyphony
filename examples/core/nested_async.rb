# frozen_string_literal: true

require 'modulation'

Rubato = import('../../lib/rubato')

spawn do
  puts "going to sleep"
  result = await async do
    await async do
      await async do
        puts "Fiber count: #{Rubato::FiberPool.size}"
        await sleep(1)
      end
    end
  end
  puts "result: #{result}"
end
