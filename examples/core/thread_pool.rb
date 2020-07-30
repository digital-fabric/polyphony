# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

def lengthy_op
  data = IO.orig_read(__FILE__)
  data.bytesize
end

10.times do |_i|
  spin {
    p [_i, 2, Polyphony::ThreadPool.process { lengthy_op }]
  }
end

suspend