# frozen_string_literal: true

require 'bundler/setup'
require 'fiber'
require_relative '../lib/polyphony_ext'

queue = Polyphony::LibevQueue.new

queue.push :a
queue.push :b
queue.push :c
p [queue.shift_no_wait]
queue.push :d
p [queue.shift_no_wait]
p [queue.shift_no_wait]
p [queue.shift_no_wait]
p [queue.shift_no_wait]

queue.unshift :e
p [queue.shift_no_wait]

queue.push :f
queue.push :g
p [queue.shift_no_wait]