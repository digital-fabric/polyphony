# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

X = 1_000_000

File.open('/tmp/puts.log', 'w+') do |f|
  t0 = Time.now
  X.times do
    f.puts 'a', 'b', 'c'
  end
  dt = Time.now - t0
  puts format('rate: %d/s', (X / dt))
end

File.open('/tmp/puts.log', 'w+') do |f|
  t0 = Time.now
  X.times do
    f.puts2 'a', 'b', 'c'
  end
  dt = Time.now - t0
  puts format('rate: %d/s', (X / dt))
end
