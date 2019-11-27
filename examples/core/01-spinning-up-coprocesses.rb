# frozen_string_literal: true

require 'bundler/setup'

# In order to automatically start the reactor, we need to require
# `polyphony/auto_run`. Otherwise, we can just require `polyphony`
require 'polyphony/auto_run'

def nap(tag, t)
  puts "#{Time.now} #{tag} napping for #{t} seconds..."
  sleep t
  puts "#{Time.now} #{tag} done napping"
end

# We launch two concurrent coprocesses, each sleeping for the given duration.
spin { nap(:a, 1) }
spin { nap(:b, 2) }

# Having required `polyphony/auto_run`, once our program is done, the
# libev-based event reactor is started, and runs until there's no more work left
# for it to handle.