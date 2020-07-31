# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'

stdin = IO.open(STDIN.to_i)

loop do
  print 'Say something: '
  cancel_after(3) do
    line = stdin.gets
    puts "You said: #{line}"
  end
rescue Polyphony::Cancel
  puts '<got nothing>'
end
