# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

def my_sleep(t)
  puts "going to sleep..."
  sleep t
  puts "woke up"
end

spin do
  async { my_sleep(1) }.await
end
