# frozen_string_literal: true

require 'modulation'

Nuclear = import('../../lib/nuclear')

def loop_it(number, lock)
  loop do
    await Nuclear.sleep(rand*0.2)
    await lock.synchronize do
      puts "child #{number} has the lock"
      await Nuclear.sleep(rand*0.05)
    end
  end
end

lock = Nuclear::Sync::Mutex.new
async! { loop_it(1, lock) }
async! { loop_it(2, lock) }
async! { loop_it(3, lock) }
