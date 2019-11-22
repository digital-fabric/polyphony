# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/auto_run'

COUNT = 10000

class ::Fiber
  attr_accessor :tag
end

COUNTS = Hash.new { |h, k| h[k] = 0 }

def t(tag)
  Fiber.current.tag = tag.to_s
  COUNT.times do |i|
    COUNTS[tag] += 1
    snooze
  end
  puts "#{tag} done"
rescue StandardError => e
  puts e
end

GC.disable
cp1 = spin { t(:a) }
cp2 = spin { t(:b) }

while cp1.alive? || cp2.alive?
  sleep 0.01
end

puts "counts:"
p COUNTS