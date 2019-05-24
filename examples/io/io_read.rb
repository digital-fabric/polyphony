# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

s = IO.read(__FILE__)
puts "encoding: #{s.encoding.inspect}"
puts s
puts