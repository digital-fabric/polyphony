# frozen_string_literal: true

require 'modulation'

Rubato = import('../../lib/rubato')

spawn {
  puts "going to sleep..."
  sleep 1
  puts "woke up"
}.await

puts "done"