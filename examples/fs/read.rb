# frozen_string_literal: true

require 'modulation'

Polyphony = import('../../lib/polyphony')

PATH = File.expand_path('../../../../docs/dev-journal.md', __dir__)

def raw_read_file(x)
  t0 = Time.now
  x.times { IO.orig_read(PATH) }
  puts "raw_read_file: #{Time.now - t0}"
end

X = 100
Y = 10

async def async_read_file
  X.times { IO.read(PATH) }
end

def do_read(supervisor, x)
  x.times { nexus << async { read_file } }
end

raw_read_file(X * Y)

spawn do
  t0 = Time.now
  supervise do |s|
    4.times { s.spawn async_read_file }
  end
  puts "thread_pool_read_file: #{Time.now - t0}"
rescue Exception => e
  p e
  puts e.backtrace.join("\n")
end
