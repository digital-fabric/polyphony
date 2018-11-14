# frozen_string_literal: true

require 'modulation'

Rubato = import('../../lib/rubato')

def loop_it(number, lock)
  loop do
    await sleep(rand*0.2)
    await lock.synchronize do
      puts "child #{number} has the lock"
      await sleep(rand*0.05)
    end
  end
end

lock = Rubato::Sync::Mutex.new
spawn { loop_it(1, lock) }
spawn { loop_it(2, lock) }
spawn { loop_it(3, lock) }
