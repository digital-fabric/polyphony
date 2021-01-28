# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

def process
  p :b_start
  sleep 1
  p :b_stop
end

spin do
  p :a_start
  spin { process }
  sleep 60
  p :a_stop
end

p :main_start
sleep 120
p :main_stop