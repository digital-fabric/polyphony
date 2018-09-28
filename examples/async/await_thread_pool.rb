# frozen_string_literal: true

require 'modulation'
require 'digest'

Nuclear     = import('../../lib/nuclear')
ThreadPool  = import('../../lib/nuclear/thread_pool')

def hash_file
  ThreadPool.process do
    Digest::SHA256.digest(IO.read('doc/Promise.html'))
  end
end

Nuclear.async do
  begin
    timer_id = Nuclear.interval(1) { puts Time.now }
    puts "hashing file..."
    t0 = Time.now
    Nuclear.await *(1000.times.map { hash_file })
    puts "hashing done (#{Time.now - t0})"
    Nuclear.cancel_timer(timer_id)
  rescue => e
    p e
    puts e.backtrace.join("\n")
  end
end
