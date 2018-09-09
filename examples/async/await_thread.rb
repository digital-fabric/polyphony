# frozen_string_literal: true

require 'modulation'

Nuclear = import('../../lib/nuclear')

def count_to(x)
  Nuclear::Thread.spawn do
    count = 0
    while count < x
      Kernel.sleep 0.1
      count += 1
    end
  end
end

Nuclear.async do
  begin
    timer_id = Nuclear.interval(1) { puts Time.now }
    puts "counting to 30..."
    Nuclear.await count_to(30)
    puts "counter done"
    Nuclear.cancel_timer(timer_id)
  rescue => e
    p e
    puts e.backtrace.join("\n")
  end
end
