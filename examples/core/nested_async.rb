# frozen_string_literal: true

require 'modulation'

Rubato = import('../../lib/rubato')

spawn do
  puts "going to sleep"
  result = async do
    async do
      async do
        puts "Fiber count: #{Rubato::FiberPool.size}"
        sleep(1)
      end.await
    end.await
  end.await
  puts "result: #{result}"
end
