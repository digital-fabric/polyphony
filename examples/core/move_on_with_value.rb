# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'
Exception.__disable_sanitized_backtrace__ = true

def blocking_operation
  sleep 60
  :foo
end

puts 'going to sleep...'
value = move_on_after(1, with_value: :bar) { blocking_operation }
puts "got value #{value.inspect}"
