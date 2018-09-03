# frozen_string_literal: true

require 'modulation'

Reactor = import('../../lib/nuclear/reactor')
extend import('../../lib/nuclear/concurrency')

running = true

async do
  while running do
    await sleep(1)
    puts Time.now
  end
  puts "done with timer"
end

async do
  await sleep(5)
  running = false
end