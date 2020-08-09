# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'
require 'io/console'

c = STDIN.raw(min: 1, tim: 0, &:getbyte)
p result: c
exit

puts '?' * 40
c = STDIN.getbyte
puts '*' * 40
p c
