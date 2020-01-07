# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'
require 'httparty'

timer = spin { throttled_loop(100) { 
  STDOUT << '.'
} }

res = HTTParty.get('http://worldtimeapi.org/api/timezone/Europe/Paris')
puts res
timer.stop