# frozen_string_literal: true

require 'modulation'

Core = import('../../lib/nuclear/core')

include Core::Async

def count_to(x)
  Core::Thread.spawn do
    count = 0
    while count < x
      Kernel.sleep 0.1
      count += 1
    end
  end
end

async do
  begin
    timer_id = Core::Reactor.interval(1) { puts Time.now }
    puts "counting to 30..."
    await count_to(30)
    puts "counter done"
    Core::Reactor.cancel_timer(timer_id)
  rescue => e
    p e
    puts e.backtrace.join("\n")
  end
end
