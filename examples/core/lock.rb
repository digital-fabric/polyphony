# frozen_string_literal: true

require 'modulation'

Nuclear = import('../../lib/nuclear')

def loop_it(number, lock)
  loop do
    lock.acquire do
      puts "child #{number} has the lock"
      await Nuclear.sleep(0.1)
    end
  end
end

lock = Nuclear::Sync::Mutex.new
async! { loop_it(1, lock) }
async! { loop_it(2, lock) }
async! { loop_it(3, lock) }
