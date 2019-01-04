# frozen_string_literal: true

require 'modulation'

Polyphony = import('../../lib/polyphony')

def loop_it(number, lock)
  loop do
    sleep(rand*0.2)
    lock.synchronize do
      puts "child #{number} has the lock"
      sleep(rand*0.05)
    end
  end
end

lock = Polyphony::Sync::Mutex.new
spawn { loop_it(1, lock) }
spawn { loop_it(2, lock) }
spawn { loop_it(3, lock) }
