# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

spin do
  puts 'two'
  # spinning a fiber from the parent fiber allows us to schedule an operation to
  # be performed even after the current fiber is terminated
  Fiber.current.parent.spin { puts 'four' }
  puts 'three'
end

puts 'one'

suspend
