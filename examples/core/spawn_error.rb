# frozen_string_literal: true

require 'modulation'

Rubato = import('../../lib/rubato')

def error(t)
  raise "hello #{t}"
end

spawn do
  error(1)
rescue => e
  puts "error: #{e.inspect}"
end

spawn do
  async { error(2) }.await
rescue => e
  puts "error: #{e.inspect}"
end

puts "done spawning"
