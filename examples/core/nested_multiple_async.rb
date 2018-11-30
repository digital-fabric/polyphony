# frozen_string_literal: true

require 'modulation'

Rubato = import('../../lib/rubato')

spawn do
  spawn do
    puts "1 >"
    sleep(1)
    puts "1 <"
  end

  spawn do
    puts "2 >"
    sleep(1)
    puts "2 <"
  end
end