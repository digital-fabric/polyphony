# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

@op_count = 0

def lengthy_op
  100.times do
    orig_sleep 0.01
    @op_count += 1
  end
  @op_count
end

spin do
  cancel_after(0.1) do
    data = Polyphony::Thread.process { lengthy_op }
    puts "slept #{data} times"
  end
rescue Exception => e
  puts "error: #{e}"
ensure
  sleep 0.1
  puts "slept #{@op_count} times"
end

suspend