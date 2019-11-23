# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'
require 'httparty'

timer = spin { throttled_loop(10) { STDOUT << '.' } }

puts HTTParty.get('http://google.com/')
timer.stop
