# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

def error(t)
  raise "hello #{t}"
end

def spin_with_error
  spin { error(2) }
end

spin_with_error

puts 'done coprocing'
suspend