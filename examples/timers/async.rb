# frozen_string_literal: true

require 'modulation'

Core = import('../../lib/nuclear/core')
include Core::Async

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