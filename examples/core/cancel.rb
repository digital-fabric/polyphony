# frozen_string_literal: true

require 'modulation'

Rubato = import('../../lib/rubato')

spawn do
  puts "going to sleep..."
  cancel_after(1) do
    await sleep 60
  end
rescue Rubato::Cancelled => e
  puts "got error: #{e}"
ensure
  puts "woke up"
end
