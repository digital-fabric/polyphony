# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

coproc {
  throttled_loop(3) { STDOUT << '.' }
}

coproc {
  throttled_loop(rate: 2) { STDOUT << '?' }
}

coproc {
  throttled_loop(interval: 1) { STDOUT << '*' }
}
