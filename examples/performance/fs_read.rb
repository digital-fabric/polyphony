# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'
require 'polyphony/adapters/fs'

def raw_read_file(x)
  t0 = Time.now
  x.times { IO.orig_read(__FILE__) }
  puts "raw_read_file: #{Time.now - t0}"
end

def threaded_read_file(x, y)
  t0 = Time.now
  threads = []
  y.times do
    threads << Thread.new { x.times { IO.orig_read(__FILE__) } }
  end
  threads.each(&:join)
  puts "threaded_read_file: #{Time.now - t0}"
end

def thread_pool_read_file(x, y)
  t0 = Time.now
  y.times do
    spin { x.times { IO.read(__FILE__) } }
  end
  Fiber.current.await_all_children
  puts "thread_pool_read_file: #{Time.now - t0}"
end

Y = ARGV[0] ? ARGV[0].to_i : 10
X = ARGV[1] ? ARGV[1].to_i : 100

raw_read_file(X * Y)
threaded_read_file(X, Y)
thread_pool_read_file(X, Y)
