# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'
require 'polyphony/core/sync'

def loop_it(number, lock)
  loop do
    sleep(rand * 0.2)
    lock.synchronize do
      puts "child #{number} has the lock"
      sleep(rand * 0.05)
    end
  end
end

lock = Polyphony::Mutex.new
spin { loop_it(1, lock) }
spin { loop_it(2, lock) }
spin { loop_it(3, lock) }

suspend