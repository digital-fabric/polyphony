# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

spin {
  1.times {
    puts Time.now
    sleep 1
  }
}

suspend
