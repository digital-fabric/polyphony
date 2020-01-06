# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

COUNT = 10_000

class ::Fiber
  attr_accessor :tag
end

COUNTS = Hash.new { |h, k| h[k] = 0 }

def t(tag)
  Fiber.current.tag = tag.to_s
  COUNT.times do
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

sleep 0.01 while cp1.alive? || cp2.alive?

puts 'counts:'
p COUNTS
