# frozen_string_literal: true

require 'modulation'

Polyphony = import('../../lib/polyphony')

def my_sleep(t)
  puts "going to sleep..."
  sleep t
  puts "woke up"
end

spawn do
  async { my_sleep(1) }.await
end
