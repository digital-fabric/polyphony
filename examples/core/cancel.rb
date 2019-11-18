# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/auto_run'

begin
  puts 'going to sleep...'
  cancel_after(1) do
    sleep(60)
  end
rescue Polyphony::Cancel
  puts 'cancelled'
end
