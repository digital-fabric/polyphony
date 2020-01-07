# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

def lengthy_op
  10.times { IO.orig_read(__FILE__) }
end

X = 1000

def blocking
  t0 = Time.now
  data = lengthy_op
  X.times { lengthy_op }
  puts "read blocking (#{Time.now - t0}s)"
end

def threaded
  t0 = Time.now
  data = Polyphony::Thread.process { lengthy_op }
  X.times { Polyphony::Thread.process { lengthy_op } }
  puts "read threaded (#{Time.now - t0}s)"
end

blocking
threaded
