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

# Thread.new do
#   loop do
#     raw_read_file
#   end
# end

def read_file
  Nuclear::FS.read(PATH)
end

def do_read(x)
  puts "reading file #{x} times..."
  t0 = Time.now
  Nuclear.await *(x.times.map { read_file })
  puts "reading done (#{Time.now - t0})"
end

Nuclear.async do
  begin
    timer_id = Nuclear.interval(1) { puts Time.now }
    do_read(1000)
    Nuclear.cancel_timer(timer_id)
  rescue => e
    p e
    puts e.backtrace.join("\n")
  end
end
