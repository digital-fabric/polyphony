# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

defer do
  puts 'two'
  defer { puts 'four' }
  puts 'three'
end

puts 'one'

suspend