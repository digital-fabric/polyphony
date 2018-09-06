# frozen_string_literal: true

require 'modulation'

Core = import('../../lib/nuclear/core')
include Core::Async

counter = 0
incrementer = nil

async do
  t0 = Time.now

  count_to_10 = promise(timeout: 1) do |promise|
    incrementer = Core::Reactor.interval(0.25) do
      counter += 1
      promise.resolve(true) if counter == 10
    end
  end
  
  await count_to_10
  puts "elapsed: #{Time.now - t0}"
  exit
rescue => e
  puts "Got error: #{e.inspect}"
ensure
  puts "cancelling incrementer"
  Core::Reactor.cancel_timer(incrementer)
end
