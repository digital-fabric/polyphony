# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

puts '* pre'
Polyphony.backend_test(STDOUT, "Hello, world!\n")
puts '* post'
