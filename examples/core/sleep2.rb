# frozen_string_literal: true

require 'modulation'

Polyphony = import('../../lib/polyphony')

spawn {
  puts "going to sleep..."
  sleep 1
  puts "woke up"
}.await

puts "done"