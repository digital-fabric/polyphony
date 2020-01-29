# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

spin do
  puts 'two'
  spin { puts 'four' }
  puts 'three'
end

puts 'one'

suspend