# frozen_string_literal: true

require 'modulation'

Nuclear = import('../../lib/nuclear')

spawn do
  puts "going to sleep..."
  cancel_after(1) do
    await Nuclear.sleep 60
  end
rescue Cancelled => e
  puts "got error: #{e}"
ensure
  puts "woke up"
end
