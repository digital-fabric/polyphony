# frozen_string_literal: true

require 'bundler/setup'

require 'polyphony'

def nap(tag, t)
  puts "#{Time.now} #{tag} napping for #{t} seconds..."
  sleep t
  puts "#{Time.now} #{tag} done napping"
end

spin { nap(:a, 1) }

# Wait for any coprocess still alive
suspend