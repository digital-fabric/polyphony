# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

spin {
  throttled_loop(3) { STDOUT << '.' }
}

spin {
  throttled_loop(rate: 2) { STDOUT << '?' }
}

spin {
  throttled_loop(interval: 1) { STDOUT << '*' }
}
