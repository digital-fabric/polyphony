# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

spawn do
  spawn do
    puts "1 >"
    sleep(1)
    puts "1 <"
  end

  spawn do
    puts "2 >"
    sleep(1)
    puts "2 <"
  end
end