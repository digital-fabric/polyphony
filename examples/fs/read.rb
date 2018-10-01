# frozen_string_literal: true

require 'modulation'

Nuclear = import('../../lib/nuclear')
Nuclear::ThreadPool.setup; sleep 0.2

PATH = File.expand_path('../../doc/Promise.html', __dir__)

def raw_read_file(x)
  t0 = Time.now
  x.times { IO.read(PATH) }
  puts "raw_read_file: #{Time.now - t0}"
end

raw_read_file(1000)

def read_file
  Nuclear::FS.read(PATH)
end

def do_read(x)
  t0 = Time.now
  Nuclear.await *(x.times.map { read_file })
  puts "thread_pool_read_file: #{Time.now - t0}"
end

Nuclear.async do
  begin
    timer = Nuclear.interval(1) { puts Time.now }
    do_read(1000)
    timer.stop
  rescue => e
    p e
    puts e.backtrace.join("\n")
  end
end
