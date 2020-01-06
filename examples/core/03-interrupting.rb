# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

# Let's see how a long-running blocking operation can be interrupted. Polyphony
# provides several APIs for interrupting an ongoing operation, and distinguishes
# between two different types of interruptions: *cancel* and *move on*. A
# *cancel* will interrupt an ongoing operation and raise an exception. A *move
# on* will interrupt an ongoing operation without raising an exception,
# optionally returning an arbitrary value as the result of that operation.

def nap(tag, t)
  puts "#{Time.now} #{tag} napping for #{t} seconds..."
  sleep t
ensure
  puts "#{Time.now} #{tag} done napping"
end

# The Kernel#cancel_after interrupts a blocking operation by raising a
# Polyphony::Cancel exception after the given timeout
spin do
  # cancel after 1 second
  cancel_after(1) { nap(:cancel, 2) }
rescue Polyphony::Cancel => e
  puts "got exception: #{e}"
end

spin do
  # move on after 1 second
  move_on_after(1) do
    nap(:move_on, 2)
  end
end

suspend