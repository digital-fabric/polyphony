# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

Exception.__disable_sanitized_backtrace__ = true

loop {
  puts "sleep"
  sleep 1
}