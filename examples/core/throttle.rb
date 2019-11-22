# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/auto_run'

spin do
  throttled_loop(3) { STDOUT << '.' }
end

spin do
  throttled_loop(rate: 2) { STDOUT << '?' }
end

spin do
  throttled_loop(interval: 1) { STDOUT << '*' }
end
