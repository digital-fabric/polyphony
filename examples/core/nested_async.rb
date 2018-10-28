# frozen_string_literal: true

require 'modulation'

Nuclear = import('../../lib/nuclear')

spawn do
  puts "going to sleep"
  result = await async do
    await async do
      await async do
        puts "Fiber count: #{Nuclear::FiberPool.size}"
        await sleep(1)
      end
    end
  end
  puts "result: #{result}"
end
