# frozen_string_literal: true

require 'modulation'

Rubato = import('../../lib/rubato')

def my_sleep(t)
  puts "going to sleep..."
  await sleep t
  puts "woke up"
end

spawn do
  await { my_sleep(1) }
end
