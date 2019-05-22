# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'
require 'polyphony/fs'

PATH = File.expand_path('../../../../docs/dev-journal.md', __dir__)

def raw_read_file(x)
  t0 = Time.now
  x.times { IO.orig_read(PATH) }
  puts "raw_read_file: #{Time.now - t0}"
end

def threaded_read_file(x, y)
  t0 = Time.now
  threads = []
  y.times {
    threads << Thread.new { x.times { IO.orig_read(PATH) } }
  }
  threads.each(&:join)
  puts "threaded_read_file: #{Time.now - t0}"
end

def thread_pool_read_file(x, y)
  t0 = Time.now
  supervise do |s|
    y.times {
      s.spawn { x.times { IO.read(PATH) } }
    }
  end
  puts "thread_pool_read_file: #{Time.now - t0}"
end

Y = ARGV[0] ? ARGV[0].to_i : 10
X = ARGV[1] ? ARGV[1].to_i : 100

raw_read_file(X * Y)
threaded_read_file(X, Y)
thread_pool_read_file(X, Y)