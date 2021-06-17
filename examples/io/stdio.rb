# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

puts 'Please enter your name:'
name = gets.chomp
puts "Hello, #{name}!"