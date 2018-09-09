# frozen_string_literal: true

require 'modulation'

Nuclear = import('../../lib/nuclear')

running = true

Nuclear.async do
  while running do
    Nuclear.await Nuclear.sleep(1)
    puts Time.now
  end
  puts "done with timer"
end

Nuclear.async do
  Nuclear.await Nuclear.sleep(5)
  running = false
end