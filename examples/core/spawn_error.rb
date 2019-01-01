# frozen_string_literal: true

require 'modulation'

Rubato = import('../../lib/rubato')
Rubato.debug = true

def error(t)
  raise "hello #{t}"
end

def spawn_with_error
  spawn { error(2) }
end

spawn do
  error(1)
rescue => e
  e.cleanup_backtrace
  puts "error: #{e.inspect}"
  puts "backtrace:"
  puts e.backtrace.reverse.join("\n")
  puts
end

spawn_with_error

puts "done spawning"
