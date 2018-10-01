# frozen_string_literal: true

require 'modulation'
require 'digest'

Nuclear     = import('../../lib/nuclear')

def hash_file
  Nuclear::ThreadPool.process do
    Digest::SHA256.digest(IO.read('doc/Promise.html'))
  end
end

Nuclear.async do
  begin
    puts "hashing file..."
    t0 = Time.now
    Nuclear.await *(1000.times.map { hash_file })
    puts "hashing done (#{Time.now - t0})"
  rescue => e
    p e
    puts e.backtrace.join("\n")
  end
end
