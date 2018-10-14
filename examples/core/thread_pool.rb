# frozen_string_literal: true

require 'modulation'
require 'digest'
require 'socket'

Nuclear     = import('../../lib/nuclear')

def lengthy_op
  # Socket.getaddrinfo('debian.org', 80)
  Digest::SHA256.digest(IO.read('doc/Promise.html'))
end

X = 1000


async def compare_performance
  t0 = Time.now
  X.times { lengthy_op }
  native_perf = X / (Time.now - t0)
  puts "native performance: #{native_perf}"

  begin
    loop do
      puts "testing async performance..."
      t0 = Time.now
      X.times do
        await Nuclear::ThreadPool.process { lengthy_op }
      end
      async_perf = X / (Time.now - t0)
      puts "async performance: %g (%.2g%%)" % [
        async_perf, async_perf / native_perf * 100
      ]

      loop do
        puts "*" * 40
        puts "testing thread pool performance..."
        t0 = Time.now
        await nexus do |n|
          X.times do
            n << Nuclear::ThreadPool.process { lengthy_op }
          end
        end
        thread_pool_perf = X / (Time.now - t0)
        puts "thread pool performance: %g (%.2g%%)" % [
          thread_pool_perf, thread_pool_perf / native_perf * 100
        ]
      end

      break
    end
  rescue => e
    p e
    puts e.backtrace.join("\n")
  end
end

compare_performance.run!