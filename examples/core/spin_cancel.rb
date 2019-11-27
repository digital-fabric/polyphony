# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/auto_run'

spin do
  cancel_after(1) do
    spin do
      puts 'going to sleep...'
      sleep(2)
    ensure
      puts 'woke up'
    end.await
  end
rescue Polyphony::Cancel => e
  puts "got error: #{e}"
end
