# frozen_string_literal: true
require 'modulation'

Reactor = import('../../lib/nuclear/reactor')
Concurrency = import('../../lib/nuclear/concurrency')

counter = 0
incrementer = nil

Concurrency.async do
  t0 = Time.now

  count_to_10 = Concurrency.promise(timeout: 1) do |promise|
    incrementer = Reactor.interval(0.25) do
      counter += 1
      promise.resolve(true) if counter == 10
    end
  end
  
  Concurrency.await count_to_10
  puts "elapsed: #{Time.now - t0}"
  exit
rescue => e
  puts "Got error: #{e.inspect}"
ensure
  puts "cancelling incrementer"
  Reactor.cancel_timer(incrementer)
end
