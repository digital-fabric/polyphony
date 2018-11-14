# frozen_string_literal: true

require 'modulation'

Rubato = import('../../lib/rubato')

spawn do
  puts "going to sleep..."
  cancel_after(1) do
    await sleep(60)
  end
rescue Rubato::Cancel => e
  puts "got error: #{e}"
ensure
  puts "woke up"
end
