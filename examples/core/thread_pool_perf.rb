# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

def lengthy_op
  data = IO.orig_read(__FILE__)
  data.clear
  # Socket.getaddrinfo('debian.org', 80)
  # Digest::SHA256.digest(IO.read('doc/Promise.html'))
end

X = 100

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
      puts format(
        'seq thread pool performance: %g (X %0.2f)',
        async_perf,
        async_perf / native_perf
      )
    end

    acc = 0
    count = 0
    10.times do |_i|
      t0 = Time.now
      supervise do |s|
        X.times do
          s.spin { Polyphony::ThreadPool.process { lengthy_op } }
        end
      end
      thread_pool_perf = X / (Time.now - t0)
      acc += thread_pool_perf
      count += 1
    end
    avg_perf = acc / count
    puts format(
      'avg thread pool performance: %g (X %0.2f)',
      avg_perf,
      avg_perf / native_perf
    )
  rescue Exception => e
    p e
    puts e.backtrace.join("\n")
  end
end

spin { compare_performance }

suspend