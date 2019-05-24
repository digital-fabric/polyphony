# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

Polyphony.debug = true

def error(t)
  raise "hello #{t}"
end

def coproc_with_error
  coproc { error(2) }
end

coproc do
  error(1)
rescue => e
  e.cleanup_backtrace
  puts "error: #{e.inspect}"
  puts "backtrace:"
  puts e.backtrace.reverse.join("\n")
  puts
end

coproc_with_error

puts "done coprocing"
