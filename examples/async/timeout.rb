# frozen_string_literal: true

require 'modulation'

Nuclear = import('../../lib/nuclear')

counter = 0
incrementer = nil

Nuclear.async do
  t0 = Time.now

  count_to_10 = Nuclear.promise(timeout: 1) do |promise|
    incrementer = Nuclear.interval(0.25) do
      counter += 1
      promise.resolve(true) if counter == 10
    end
  end
  
  Nuclear.await count_to_10
  puts "elapsed: #{Time.now - t0}"
  exit
rescue => e
  puts "Got error: #{e.inspect}"
ensure
  puts "cancelling incrementer"
  incrementer.stop
end
