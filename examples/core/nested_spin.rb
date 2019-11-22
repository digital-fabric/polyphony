# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/auto_run'

spin do
  puts 'going to sleep'
  result = spin do
    spin do
      spin do
        puts "Fiber count: #{Polyphony::FiberPool.stats[:total]}"
        sleep(1)
      end.await
    end.await
  end.await
  puts "result: #{result}"
end
