# frozen_string_literal: true

require 'modulation'

Rubato = import('../../lib/rubato')

spawn do
  stdin = STDIN#Rubato::IO::IOWrapper.new(STDIN)
  puts "Write something..."
  cancel_after(10) do |scope|
    loop do
      data = stdin.read
      scope.reset_timeout
      puts "you wrote: #{data}"
    end
  end
rescue Rubato::Cancel
  puts "quitting due to inactivity"
end
