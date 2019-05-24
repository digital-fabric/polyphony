# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

coproc do
  coproc do
    puts "1 >"
    sleep(1)
    puts "1 <"
  end

  coproc do
    puts "2 >"
    sleep(1)
    puts "2 <"
  end
end