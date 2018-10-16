# frozen_string_literal: true

require 'modulation'

Nuclear = import('../../lib/nuclear')

async! do
  puts "going to sleep..."
  cancel_after(1) do
    await async do
      await Nuclear.sleep 2
    end
  end
rescue Cancelled => e
  puts "got error: #{e}"
ensure
  puts "woke up"
end

