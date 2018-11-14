# frozen_string_literal: true

require 'modulation'

Rubato = import('../../lib/rubato')
Rubato::ThreadPool.setup; sleep 0.2

PATH = File.expand_path('../../doc/Promise.html', __dir__)

def raw_read_file(x)
  t0 = Time.now
  x.times { IO.read(PATH) }
  puts "raw_read_file: #{Time.now - t0}"
end

def read_file
  await Rubato::FS.read(PATH)
end

def do_read(nexus, x)
  x.times { nexus << async { read_file } }
end

X = 100

raw_read_file(X)

spawn do
  t0 = Time.now
  await nexus do |n|
    # n << async { Rubato.pulse(1) { puts Time.now } }
    do_read(n, X)
  end
  puts "thread_pool_read_file: #{Time.now - t0}"
rescue Exception => e
  p e
  puts e.backtrace.join("\n")
end
