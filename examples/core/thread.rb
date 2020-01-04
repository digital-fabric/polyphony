# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

def lengthy_op
  IO.orig_read(__FILE__)
end

X = 10000

def blocking
  t0 = Time.now
  data = lengthy_op
  X.times { lengthy_op }
  puts "read blocking #{data.bytesize} bytes (#{Time.now - t0}s)"
end

def threaded
  t0 = Time.now
  data = Polyphony::Thread.spawn { lengthy_op }.await
  X.times { Polyphony::Thread.spawn { lengthy_op } }
  puts "read threaded #{data.bytesize} bytes (#{Time.now - t0}s)"
end

blocking
threaded
