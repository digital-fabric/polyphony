# frozen_string_literal: true

require 'modulation'

Rubato = import('../../lib/rubato')

def error(t)
  raise "hello"
end

spawn do
  async { error(1) }.await
end

puts "after spawn"
