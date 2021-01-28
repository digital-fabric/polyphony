# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

main = Fiber.current
spin do
  sleep 0.1
  main.schedule(:foo)
end

v = suspend
puts "v => #{v.inspect}"
