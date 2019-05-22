# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

puts "going to sleep..."
cancel_after(1) do
  sleep(60)
end
