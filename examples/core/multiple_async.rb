# frozen_string_literal: true

require 'modulation'

Nuclear = import('../../lib/nuclear')

async! do
  puts "1 >"
  await Nuclear.sleep(1)
  puts "1 <"
end

async! do
  puts "2 >"
  await Nuclear.sleep(1)
  puts "2 <"
end
