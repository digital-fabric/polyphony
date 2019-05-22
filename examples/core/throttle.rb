# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

spawn {
  throttled_loop(3) { STDOUT << '.' }
}

spawn {
  throttled_loop(rate: 2) { STDOUT << '?' }
}

spawn {
  throttled_loop(interval: 1) { STDOUT << '*' }
}
