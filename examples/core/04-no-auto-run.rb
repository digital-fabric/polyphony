# frozen_string_literal: true

require 'bundler/setup'

# Notice we require 'polyphony' and not 'polyphony/auto_run'
require 'polyphony'

def nap(tag, t)
  puts "#{Time.now} #{tag} napping for #{t} seconds..."
  sleep t
  puts "#{Time.now} #{tag} done napping"
end

spin { nap(:a, 1) }

# If polyphony/auto_run has not been `require`d, the reactor fiber needs to be
# started manually. This is done by transferring control to it using `suspend`:
suspend