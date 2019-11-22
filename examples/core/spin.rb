# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/auto_run'

def my_sleep(t)
  puts 'going to sleep...'
  sleep t
  puts 'woke up'
end

spin do
  spin { my_sleep(1) }.await
end
