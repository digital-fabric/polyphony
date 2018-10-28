# frozen_string_literal: true

require 'modulation'

Nuclear = import('../../lib/nuclear')

spawn do
  puts "going to sleep..."
  await sleep 1
  puts "woke up"
end
