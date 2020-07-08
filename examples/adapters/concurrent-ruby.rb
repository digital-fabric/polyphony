# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'
require 'concurrent'

puts "Hello, concurrent-ruby"

# this program should not hang with concurrent-ruby 1.1.6 (see issue #22)
