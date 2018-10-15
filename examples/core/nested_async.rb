# frozen_string_literal: true

require 'modulation'

Nuclear = import('../../lib/nuclear')

async! do
  puts "going to sleep"
  result = await async do
    await async do
      await async do
        puts "Fiber count: #{Nuclear::FiberPool.size}"
        await Nuclear.sleep(1)
      end
    end
  end
  puts "result: #{result}"
end
