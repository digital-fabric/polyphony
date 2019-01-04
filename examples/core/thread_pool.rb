# frozen_string_literal: true

require 'modulation'
require 'digest'
require 'socket'

Polyphony = import('../../lib/polyphony')

def lengthy_op
  data = IO.read('../../docs/reality-ui.bmpr')
  data.clear
  # Socket.getaddrinfo('debian.org', 80)
  #Digest::SHA256.digest(IO.read('doc/Promise.html'))
end

X = 1000

def compare_performance
  t0 = Time.now
  X.times { lengthy_op }
  native_perf = X / (Time.now - t0)
  puts "native performance: #{native_perf}"
  # puts "*" * 40

  begin
    1.times do
      t0 = Time.now
      X.times do
        Polyphony::ThreadPool.process { lengthy_op }
      end
      async_perf = X / (Time.now - t0)
      puts "seq thread pool performance: %g (X %0.2f)" % [
        async_perf, async_perf / native_perf
      ]
    end

    acc = 0
    count = 0
    10.times do |i|
      t0 = Time.now
      supervise do |s|
        X.times do
          s.spawn Polyphony::ThreadPool.process { lengthy_op }
        end
      end
      thread_pool_perf = X / (Time.now - t0)
      acc += thread_pool_perf
      count += 1
    end
    avg_perf = acc / count
    puts "avg thread pool performance: %g (X %0.2f)" % [
      avg_perf, avg_perf / native_perf
    ]
rescue Exception => e
    p e
    puts e.backtrace.join("\n")
  end
end

spawn { compare_performance }