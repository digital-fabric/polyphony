# frozen_string_literal: true

require 'modulation'
require 'digest'
require 'socket'

Rubato     = import('../../lib/rubato')

def lengthy_op
  IO.read('../../docs/reality-ui.bmpr')
end

def blocking
  t0 = Time.now
  data = lengthy_op
  9.times { lengthy_op }
  puts "read blocking #{data.bytesize} bytes (#{Time.now - t0}s)"
end

def threaded
  t0 = Time.now
  data = Rubato::Thread.spawn { lengthy_op }.await
  9.times { Rubato::Thread.spawn { lengthy_op }.await }
  puts "read threaded #{data.bytesize} bytes (#{Time.now - t0}s)"
end

spawn do
  blocking
  threaded
end
