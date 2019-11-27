# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony/auto_run'

@op_count = 0

def lengthy_op
  100.times do
    sleep 0.01
    @op_count += 1
  end
  @op_count
end

spin do
  t0 = Time.now
  cancel_after(0.1) do
    data = Polyphony::Thread.spin { lengthy_op }.await
    puts "slept #{data} times"
  end
rescue Exception => e
  puts "error: #{e}"
ensure
  puts "slept #{@op_count} times"
end
