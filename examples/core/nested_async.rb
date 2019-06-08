# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

spin do
  puts "going to sleep"
  result = async do
    async do
      async do
        puts "Fiber count: #{Polyphony::FiberPool.size}"
        sleep(1)
      end.await
    end.await
  end.await
  puts "result: #{result}"
end
