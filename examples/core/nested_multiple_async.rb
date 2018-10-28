# frozen_string_literal: true

require 'modulation'

Nuclear = import('../../lib/nuclear')

spawn do
  spawn do
    puts "1 >"
    await sleep(1)
    puts "1 <"
  end

  spawn do
    puts "2 >"
    await sleep(1)
    puts "2 <"
  end
end