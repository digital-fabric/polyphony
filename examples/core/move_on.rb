# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/auto_run'
Exception.__disable_sanitized_backtrace__ = true

puts 'going to sleep...'
move_on_after(1) do
  sleep 60
end
puts 'woke up'
