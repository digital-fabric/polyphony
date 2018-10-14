# frozen_string_literal: true

require 'modulation'

Nuclear = import('../../lib/nuclear')

async! do
  result = await async do
    await async do
      await async do
        await Nuclear.sleep(1)
      end
    end
  end
  puts "result: #{result}"
end
