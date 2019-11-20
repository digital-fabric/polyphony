# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

spin do
  puts 'going to sleep...'
  cancel_after(1) do
    async do
      sleep(2)
    end.await
  end
rescue Polyphony::Cancel => e
  puts "got error: #{e}"
ensure
  puts 'woke up'
end
