# frozen_string_literal: true

require 'modulation'

Polyphony = import('../../lib/polyphony')

spawn do
  puts "going to sleep..."
  cancel_after(1) do
    async {
      sleep(2)
    }.await
  end
rescue Polyphony::Cancel => e
  puts "got error: #{e}"
ensure
  puts "woke up"
end

