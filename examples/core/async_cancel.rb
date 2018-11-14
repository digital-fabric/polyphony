# frozen_string_literal: true

require 'modulation'

Rubato = import('../../lib/rubato')

spawn do
  puts "going to sleep..."
  cancel_after(1) do
    await async do
      await sleep 2
    end
  end
rescue Rubato::Cancelled => e
  puts "got error: #{e}"
ensure
  puts "woke up"
end

