# frozen_string_literal: true

require 'modulation'

Polyphony = import('../../lib/polyphony')

spawn do
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
