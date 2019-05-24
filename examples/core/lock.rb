# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

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
coproc { loop_it(1, lock) }
coproc { loop_it(2, lock) }
coproc { loop_it(3, lock) }
