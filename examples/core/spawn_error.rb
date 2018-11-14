# frozen_string_literal: true

require 'modulation'

Rubato = import('../../lib/rubato')

def error(t)
  raise "hello"
end

spawn do
  await { error(1) }
end

puts "after spawn"
