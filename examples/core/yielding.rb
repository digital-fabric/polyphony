# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

COUNT = 1000

class ::Fiber
  attr_accessor :tag
end

def t(tag)
  Fiber.current.tag = tag.to_s
  COUNT.times { |i|
    puts "#{tag} #{i} "
    snooze
  }
  puts
  snooze
  puts "#{tag} done"
rescue => e
  puts e
end


GC.disable
spin { t(:a) }
spin { t(:b) }