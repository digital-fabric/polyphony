# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

spin do
  1.times do
    puts Time.now
    sleep 1
  end
end

suspend
